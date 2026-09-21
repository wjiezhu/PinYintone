import Foundation

/// 「练习建议」请求的研究记录（字典 §9）。
///
/// 一行 = **一次用户点击**。未点击不自动生成、也不计作已使用。
/// 网络重传复用 `requestID`；用户再次主动点击则新建编号。
@MainActor
final class AdviceRequestLog {
    static let shared = AdviceRequestLog()
    private(set) var pending: [Record] = []
    private init() {}

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
        let now = Date()
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

    func clearPendingOnWithdrawal() { pending.removeAll() }
    func remove(_ ids: Set<UUID>) { pending.removeAll { ids.contains($0.requestID) } }
}
