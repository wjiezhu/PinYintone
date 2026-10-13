import Foundation

/// 研究数据的上报通道：退出指令、问卷、尝试、事件、建议记录。
///
/// 设计要点：
/// - **幂等靠编号**：上报失败不丢记录、不换编号，下次原样重传，服务端按主键去重。
/// - **成功才出队**：只有服务端确认过的记录才从待传队列移除。
/// - **顺序有外键依赖**（需求 §5）：身份与背景表确认 → 尝试 → 关联事件 → 建议。
///   背景表没被服务端确认之前，尝试和事件先留在本机。
/// - **区分「等一等」和「没用了」**：断网、超时、5xx 保留队列稍后重试；
///   服务端对某条记录的明确拒绝（窗口外、归属不符）则移出队列并计数，
///   不让一条坏记录堵死后面全部。
/// - **退出优先**：有待同步的退出指令时，先发它；发出去之前和之后
///   都不再上传任何研究内容（需求 R08：离线退出不能把旧队列传上去）。
/// - **不看采集窗口**：这里传的是已经合法产生的数据。窗口关闭后照样补传。
@MainActor
final class ResearchUploader {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchUploader()

    /// 单批上限。批太大时一次网络失败会拖住全部记录，也容易触发服务端体积限制。
    static let batchSize = 50

    private var isUploading = false
    private var flushRequestedWhileBusy = false

    private init() {}

    struct EventBatch: Encodable {
        let participantID: String
        let manifestID: String
        let events: [ResearchEvent]
    }

    struct AttemptBatch: Encodable {
        let participantID: String
        let manifestID: String
        let attempts: [ResearchAttemptRecord]
    }

    struct AdviceBatch: Encodable {
        let participantID: String
        let manifestID: String
        let requests: [AdviceRequestLog.Record]
    }

    /// 有新内容入队时调用。不等结果，失败留给下一次。
    func scheduleFlush() {
        Task { await flush() }
    }

    /// 尝试上报全部待传内容。返回本次服务端确认的记录条数。
    @discardableResult
    func flush() async -> Int {
        guard !isUploading else {
            flushRequestedWhileBusy = true     // 正在传：传完再跑一轮，别丢下新入队的
            return 0
        }
        isUploading = true
        var total = 0
        repeat {
            flushRequestedWhileBusy = false
            total += await flushOnce()
        } while flushRequestedWhileBusy
        isUploading = false
        return total
    }

    private func flushOnce() async -> Int {
        let store = ResearchStore.shared
        // 上传途中用户可能登出或换账号。每一步落结果前都核对还是不是同一个账号，
        // 不是就立刻停——不能把 A 的回执记到 B 的状态上。
        let account = store.accountKey
        func sameAccount() -> Bool { store.accountKey == account && account != nil }
        guard sameAccount() else { return 0 }

        // 1) 退出指令最先。它没同步成功之前，什么研究内容都不传。
        if let w = store.state.pendingWithdrawal {
            do {
                try await APIClient.shared.withdrawResearch(
                    participantID: w.participantID, consentVersion: w.consentVersion,
                    consentLanguage: w.language, occurredAt: w.occurredAt)
            } catch let error as ResearchAPIError where !error.isRetryable {
                // 服务端不认识这位参与者等：再试也一样。指令作废，端侧早已停采。
            } catch {
                return 0
            }
            guard sameAccount() else { return 0 }
            store.update { $0.pendingWithdrawal = nil }
            return 1
        }

        guard ResearchGate.canUpload(state: store.state),
              let pid = store.state.participantID,
              let mid = store.state.manifestID else { return 0 }

        var uploaded = 0

        // 2) 问卷。背景表排最前：它是服务端复核资格的依据。
        for record in SurveyCenter.recordsNeedingUpload(in: store.state) {
            let sending = record.status
            let timing = record.timingClass ?? SurveyCenter.timingClass(
                for: record.formKey, completedAt: record.invitedAt, state: store.state)
            do {
                let ack = try await APIClient.shared.uploadSurvey(
                    record, timingClass: timing, participantID: pid, manifestID: mid)
                guard sameAccount() else { return uploaded }
                // 与服务端此刻保存的状态对账（它可能已存有另一台设备提交的最终答案）
                SurveyCenter.reconcile(record.formKey, sent: sending,
                                       server: ack.status.flatMap(SurveyRecord.Status.init(rawValue:)))
                uploaded += 1
            } catch let error as ResearchAPIError {
                guard sameAccount() else { return uploaded }
                if handleRefusal(error) { return uploaded }
                if error.isRetryable { return uploaded }
                // 这份问卷被明确拒收（如窗口已关闭、版本不符）：不再重试，
                // 也**不**显示为已提交。
                SurveyCenter.markRejected(record.formKey,
                                          reason: error.reasonCode ?? "rejected")
            } catch {
                return uploaded
            }
        }

        // 背景表还没被服务端确认：尝试与事件先不传（外键与资格都依赖它）
        guard store.state.backgroundAcked else { return uploaded }

        // 3) 尝试 → 4) 事件 → 5) 建议。前一类没传完就不传后一类。
        let attemptLog = ResearchAttemptLog.shared
        while true {
            let batch = Array(attemptLog.pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            let ids = Set(batch.map(\.attemptID))
            switch await send("attempts", count: batch.count, sameAccount: sameAccount, {
                try await APIClient.shared.uploadResearchAttempts(
                    AttemptBatch(participantID: pid, manifestID: mid, attempts: batch))
            }) {
            case .done:      attemptLog.remove(ids); uploaded += batch.count
            case .stop:      return uploaded
            }
        }

        let eventLog = ResearchEventLog.shared
        while true {
            let batch = Array(eventLog.pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            let ids = Set(batch.map(\.eventID))
            switch await send("events", count: batch.count, sameAccount: sameAccount, {
                try await APIClient.shared.uploadResearchEvents(
                    EventBatch(participantID: pid, manifestID: mid, events: batch))
            }) {
            case .done:      eventLog.remove(ids); uploaded += batch.count
            case .stop:      return uploaded
            }
        }

        let adviceLog = AdviceRequestLog.shared
        while true {
            let batch = Array(adviceLog.pending.prefix(Self.batchSize))
            guard !batch.isEmpty else { break }
            let ids = Set(batch.map(\.requestID))
            switch await send("advice", count: batch.count, sameAccount: sameAccount, {
                try await APIClient.shared.uploadResearchAdvice(
                    AdviceBatch(participantID: pid, manifestID: mid, requests: batch))
            }) {
            case .done:      adviceLog.remove(ids); uploaded += batch.count
            case .stop:      return uploaded
            }
        }
        return uploaded
    }

    private enum Outcome { case done, stop }

    /// 发一批。`.done` = 这批处理完了，可以出队（入库、重复或被明确拒收）；
    /// `.stop` = 这一轮到此为止（稍后重试，或换了账号，或已被服务端停收）。
    private func send(_ queue: String, count: Int, sameAccount: () -> Bool,
                      _ call: () async throws -> APIClient.BatchAck) async -> Outcome {
        do {
            let ack = try await call()
            guard sameAccount() else { return .stop }
            ResearchStore.shared.addDeadLetters(ack.rejected?.count ?? 0, queue: queue)
            return .done
        } catch let error as ResearchAPIError {
            guard sameAccount() else { return .stop }
            if handleRefusal(error) { return .stop }
            if error.isRetryable { return .stop }
            // 整批被明确拒绝（格式不被接受等）。重传不会有不同结果：
            // 记入拒收计数后出队，不让它永远堵在队首。
            ResearchStore.shared.addDeadLetters(count, queue: queue)
            return .done
        } catch {
            return .stop
        }
    }

    /// 服务端表示「不再接收这位参与者的研究数据」时，端侧跟着停。
    /// 返回 true 表示已处理、本轮上传应当结束。
    ///
    /// 两种情形：服务端已无有效同意（例如在另一台设备上退出了、或账号已删除），
    /// 或背景表复核后不符合纳入条件。都要立即停采并清空待传内容——
    /// 继续攒着只会永远发不出去。
    private func handleRefusal(_ error: ResearchAPIError) -> Bool {
        guard error.status == 403 else { return false }
        let notEligible = error.reasonCode == "not_eligible"
        ResearchEnrollment.stopLocally(as: notEligible ? .ineligible : .withdrawn)
        return true
    }
}
