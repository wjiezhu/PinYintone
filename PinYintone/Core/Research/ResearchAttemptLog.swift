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
@MainActor
final class ResearchAttemptLog {
    static let shared = ResearchAttemptLog()

    private(set) var pending: [ResearchAttemptRecord] = []
    /// 进行中的尝试，按 attemptID 索引；结束时移入 pending
    private var inFlight: [UUID: ResearchAttemptRecord] = [:]
    private var startUptime: [UUID: TimeInterval] = [:]

    private init() {}

    private var isCollecting: Bool { ResearchEventLog.shared.isCollecting }

    /// 开始一次尝试（= 开始录音）。进入词页但没录音不调用本方法。
    func begin(attemptID: UUID, taskType: ResearchAttemptRecord.TaskType,
               lexemeVersionID: String?, priorPracticeCount: Int?,
               retryOf: UUID? = nil, now: Date = Date()) {
        guard isCollecting else { return }
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
    }

    /// 录音结束、开始分析
    func markAnalyzing(_ id: UUID, now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = .analyzing
        r.recordingDurationMs = elapsedMs(since: id)
        inFlight[id] = r
    }

    /// 评分成功。`metric` 是实际指标值，`passed` 是实际阈值判断。
    func markSucceeded(_ id: UUID, metric: Double, passed: Bool,
                       signal: ResearchAttemptRecord.SignalStatus = .usable,
                       now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = .succeeded
        r.finishedAt = now
        r.analysisDurationMs = elapsedMs(since: id)
        r.signalStatus = signal
        r.metricValue = metric
        r.passed = passed
        inFlight[id] = r
    }

    /// 失败。**metric 与 passed 保持 nil**——不填零分替代（需求 §7）。
    func markFailed(_ id: UUID, status: ResearchAttemptRecord.Status,
                    error: ResearchErrorCode,
                    signal: ResearchAttemptRecord.SignalStatus = .unusable,
                    now: Date = Date()) {
        guard var r = inFlight[id] else { return }
        r.status = status
        r.finishedAt = now
        r.signalStatus = signal
        r.errorCode = error
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

    /// 裸测等不展示结果的路径：直接结账，不填 resultDisplayedAt
    func finishWithoutDisplay(_ id: UUID) { flushToPending(id) }

    func clearPendingOnWithdrawal() {
        pending.removeAll()
        inFlight.removeAll()
        startUptime.removeAll()
    }

    func remove(_ ids: Set<UUID>) { pending.removeAll { ids.contains($0.attemptID) } }

    private func flushToPending(_ id: UUID) {
        guard let r = inFlight.removeValue(forKey: id) else { return }
        startUptime.removeValue(forKey: id)
        pending.append(r)
    }

    /// 单调时钟测时长：墙钟会被改动或校时，做差值会出现负数（字典 §2 要求非负）
    private func elapsedMs(since id: UUID) -> Int? {
        guard let t0 = startUptime[id] else { return nil }
        return Int(max(0, (ProcessInfo.processInfo.systemUptime - t0) * 1000))
    }
}
