import Foundation

/// 「练习建议」请求的研究记录（字典 §9）。
///
/// 一行 = **一次用户点击**。未点击不自动生成、也不计作已使用。
/// 网络重传复用 `requestID`；用户再次主动点击则新建编号。
@MainActor
final class AdviceRequestLog {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = AdviceRequestLog()
    private static let queueName = "advice"
    private(set) var pending: [Record] = []
    private init() {}

    /// 换账号后从该账号的存储域重新加载
    func reload() { pending = ResearchStore.shared.loadQueue(Self.queueName) }

    private func persist() { ResearchStore.shared.saveQueue(Self.queueName, pending) }

    nonisolated struct Record: Codable, Equatable {
        let requestID: UUID
        let attemptID: UUID?
        let requestedAt: Date
        let status: String            // pending / succeeded / failed
        /// 模板路径同样记录完成时间，但 **source_type 不声称模型生成**（字典 §9）
        let generatedAt: Date?
        let displayedAt: Date?
        let sourceType: String
        let teacherHintVersion: String?
        let evidenceCodes: [String]
        let evidenceSnapshot: [String: String]
        let outputLanguage: String?
        let outputText: String?
        let lexemeVersionID: String?
    }

    func record(advice: PracticeAdvice, attemptID: UUID?, lexemeVersionID: String?) {
        guard ResearchEventLog.shared.isCollecting else { return }
        // 建议必须挂在一次具体的尝试上（服务端该列非空）。没有尝试就不记，
        // 不造一个假的编号。
        guard attemptID != nil else { return }
        let now = Date()
        defer {
            persist()
            ResearchUploader.shared.scheduleFlushSoon()
        }
        pending.append(Record(
            requestID: UUID(),
            attemptID: attemptID,
            requestedAt: now,
            // 本地模板路径是同步完成的：请求即成功
            status: "succeeded",
            generatedAt: now,
            // 记录的是**内容已实际显示**的时间。请求成功、内容显示、学习者理解
            // 是三个不同概念（字典 §9 末），这里只能断言第二个。
            displayedAt: now,
            sourceType: advice.source.rawValue,
            teacherHintVersion: advice.teacherHintVersion,
            evidenceCodes: advice.evidence.map(\.rawValue),
            evidenceSnapshot: advice.evidenceSnapshot,
            outputLanguage: LocalizationManager.shared.language,
            outputText: NSLocalizedString(advice.mainSentenceKey, comment: ""),
            lexemeVersionID: lexemeVersionID))
    }

    func clearPendingOnWithdrawal() {
        pending.removeAll()
        persist()
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pending.removeAll { ids.contains($0.requestID) }
        persist()
    }
}
