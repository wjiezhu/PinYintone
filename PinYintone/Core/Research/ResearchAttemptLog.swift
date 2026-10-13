import Foundation

/// 一次练习尝试的研究记录（字典 §7）。
nonisolated struct ResearchAttemptRecord: Codable, Equatable {
    enum Status: String, Codable {
        case recording, cancelled
        case recordingFailed = "recording_failed"
        case analyzing
        case analysisFailed = "analysis_failed"
        case succeeded
        case interruptedUnknown = "interrupted_unknown"
    }
    enum TaskType: String, Codable {
        case fixedWord = "fixed_word"
        case freeText = "free_text"
        /// 本工程扩展：可选自测（纯裸测）。字典 v1 未含，见 docs/V2_DECISIONS.md
        case selfTest = "self_test"
    }
    enum SignalStatus: String, Codable { case unknown, usable, unusable }
    enum TimeQuality: String, Codable { case valid, suspect, unknown }

    let attemptID: UUID
    let sessionID: UUID
    let taskType: TaskType
    /// free_text 为 nil——**不存用户原文**
    let lexemeVersionID: String?
    let retryOfAttemptID: UUID?
    /// 自测时记该词此前已练过几次（决定 5：接受词集重叠，改为如实记录）
    let priorPracticeCount: Int?
    let startedAt: Date
    var status: Status
    var finishedAt: Date?
    var recordingDurationMs: Int?
    var analysisDurationMs: Int?
    var signalStatus: SignalStatus
    /// **失败或无有效指标写 nil**。
    /// 注意与旧表的区别：旧表用 -1 哨兵占住非空列，新表直接 NULL。
    /// 不要把哨兵搬过来——那个设计是被旧表的非空约束逼出来的，
    /// 且已经害我们在教师看板上把技术失败算成了通关。
    var metricValue: Double?
    /// 无有效评分或未设通过规则为 nil。**nil 不等于未通过。**
    var passed: Bool?
    var errorCode: ResearchErrorCode?
    /// 分析结果**首次成功渲染**的时间；仅拿到结果不算。
    /// 后置问卷计数只认 succeeded 且本项非空者（字典 §7 末）。
    var resultDisplayedAt: Date?
    var timeQuality: TimeQuality
}

/// 尝试记录的采集入口。与事件同样受研究门禁约束。
///
/// 一次真实录音 = 一个新的 `attempt_id`（字典 §7、需求 R07）。四种结局分别保存：
/// 有效结果、技术失败、用户取消、未知中断。后三种**没有成绩**——不是零分。
///
/// 进行中的尝试也落盘：App 在录音或分析途中被杀，下次启动时这条尝试
/// 按 `interrupted_unknown` 结账，而不是凭空消失。
@MainActor
final class ResearchAttemptLog {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchAttemptLog()

    private static let pendingQueue = "attempts"
    private static let inFlightQueue = "attempts.inflight"

    private(set) var pending: [ResearchAttemptRecord] = []
    /// 进行中的尝试，按 attemptID 索引；结束时移入 pending
    private var inFlight: [UUID: ResearchAttemptRecord] = [:]
    /// 单调时钟起点。不落盘——跨进程的时长本来就量不出来。
    private var startUptime: [UUID: TimeInterval] = [:]

    private init() {}

    /// 换账号（或启动）后重新加载。上次进程留下的进行中尝试一律是
    /// **未知中断**：我们不知道它是被系统杀掉、崩溃还是用户强退，
    /// 所以不编成取消，也不编成失败（字典 §8：未经确认的退出不得编码为 crash）。
    func reload() {
        let store = ResearchStore.shared
        pending = store.loadQueue(Self.pendingQueue)
        let orphans: [ResearchAttemptRecord] = store.loadQueue(Self.inFlightQueue)
        inFlight = [:]
        startUptime = [:]
        for var r in orphans {
            r.status = .interruptedUnknown
            r.metricValue = nil
            r.passed = nil
            r.resultDisplayedAt = nil
            // 结束时间不知道，留空；时长同样量不出来
            r.timeQuality = .unknown
            pending.append(r)
        }
        persist()
    }

    /// 开始一次尝试（= 开始录音）。进入词页但没录音不调用本方法。
    /// - Returns: 是否真的开始记录（未在采集时为 false）
    @discardableResult
    func begin(attemptID: UUID, taskType: ResearchAttemptRecord.TaskType,
               lexemeVersionID: String?, priorPracticeCount: Int?,
               retryOf: UUID? = nil, now: Date = Date()) -> Bool {
        guard ResearchGate.shouldCollect(now: now) else { return false }
        inFlight[attemptID] = ResearchAttemptRecord(
            attemptID: attemptID,
            sessionID: ResearchSession.shared.sessionID,
            taskType: taskType,
            lexemeVersionID: lexemeVersionID,
            retryOfAttemptID: retryOf,
            priorPracticeCount: priorPracticeCount,
            startedAt: now,
            status: .recording,
            finishedAt: nil,
            recordingDurationMs: nil,
            analysisDurationMs: nil,
            signalStatus: .unknown,
            metricValue: nil,
            passed: nil,
            errorCode: nil,
            resultDisplayedAt: nil,
            timeQuality: .valid)
        startUptime[attemptID] = ProcessInfo.processInfo.systemUptime
        persist()
        return true
    }

    /// 该编号的尝试是否正在被记录（已开始、尚未结账）
    func isTracking(_ id: UUID) -> Bool { inFlight[id] != nil }

    /// 录音结束、开始分析
    func markAnalyzing(_ id: UUID, now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = .analyzing
        r.recordingDurationMs = elapsedMs(since: id)
        inFlight[id] = r
        persist()
    }

    /// 评分成功。`metric` 是实际指标值，`passed` 是实际判定结果
    /// （含平调走向闸门，**不是**按阈值重算）。
    ///
    /// 指标必须是有限数：NaN / Infinity 不是成绩，按分析失败处理。
    func markSucceeded(_ id: UUID, metric: Double, passed: Bool,
                       signal: ResearchAttemptRecord.SignalStatus = .usable,
                       now: Date = Date()) {
        guard metric.isFinite, metric >= 0 else {
            markFailed(id, status: .analysisFailed, error: .analysisEngineError,
                       signal: .unusable, now: now)
            return
        }
        guard var r = inFlight[id] else { return }
        r.status = .succeeded
        r.finishedAt = now
        r.analysisDurationMs = elapsedMs(since: id)
        r.signalStatus = signal
        r.metricValue = metric
        r.passed = passed
        inFlight[id] = r
        persist()
    }

    /// 技术失败。**metric 与 passed 保持 nil**——不填零分替代（需求 R07）。
    func markFailed(_ id: UUID, status: ResearchAttemptRecord.Status,
                    error: ResearchErrorCode,
                    signal: ResearchAttemptRecord.SignalStatus = .unusable,
                    now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = status
        r.finishedAt = now
        r.signalStatus = signal
        r.metricValue = nil
        r.passed = nil
        r.errorCode = error
        inFlight[id] = r
        flushToPending(id)
    }

    /// 用户主动取消（录音中切词、退出页面、取消自测）。不是失败，也没有成绩。
    func markCancelled(_ id: UUID, now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = .cancelled
        r.finishedAt = now
        r.recordingDurationMs = r.recordingDurationMs ?? elapsedMs(since: id)
        r.metricValue = nil
        r.passed = nil
        inFlight[id] = r
        flushToPending(id)
    }

    /// 被系统打断（来电、切后台、音频会话被占用）而没能完成。
    /// 我们确知它没完成，但不确知原因，故记为未知中断。
    func markInterrupted(_ id: UUID, now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = .interruptedUnknown
        r.finishedAt = now
        r.metricValue = nil
        r.passed = nil
        inFlight[id] = r
        flushToPending(id)
    }

    /// 结果**实际渲染**到屏幕。只有这一步之后才算一次合格练习。
    func markResultDisplayed(_ id: UUID, now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.resultDisplayedAt = now
        inFlight[id] = r
        flushToPending(id)
    }

    /// 自测等不展示结果的路径：直接结账，不填 resultDisplayedAt
    func finishWithoutDisplay(_ id: UUID) { flushToPending(id) }

    func clearPendingOnWithdrawal() {
        pending.removeAll()
        inFlight.removeAll()
        startUptime.removeAll()
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pending.removeAll { ids.contains($0.attemptID) }
        persist()
    }

    private func flushToPending(_ id: UUID) {
        guard let r = inFlight.removeValue(forKey: id) else { return }
        startUptime.removeValue(forKey: id)
        pending.append(r)
        persist()
        // 这次尝试已有定论：安排上传，不等下次打开 App
        ResearchUploader.shared.scheduleFlushSoon()
    }

    private func persist() {
        let store = ResearchStore.shared
        store.saveQueue(Self.pendingQueue, pending)
        store.saveQueue(Self.inFlightQueue, Array(inFlight.values))
    }

    /// 单调时钟测时长：墙钟会被改动或校时，做差值会出现负数（字典 §2 要求非负）
    private func elapsedMs(since id: UUID) -> Int? {
        guard let t0 = startUptime[id] else { return nil }
        return Int(max(0, (ProcessInfo.processInfo.systemUptime - t0) * 1000))
    }
}
