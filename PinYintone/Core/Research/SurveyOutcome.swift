import Foundation

/// 一份问卷的作答结果。
///
/// 三种状态必须区分（字典 §11、问卷 §5）：
/// - `answered`：选了选项或填了文字
/// - `skipped`：用户**明确**跳过
/// - `notAnswered`：尚未作答
/// 不能用 NULL 推断「没有问题」——跳过与「没遇到问题」是不同的意思。
nonisolated struct SurveyAnswer: Codable, Equatable {
    enum State: String, Codable { case answered, skipped, notAnswered = "not_answered" }
    let questionID: String
    let state: State
    /// 已回答的选项码；未答为 nil。**禁止存显示标签代替选项码**
    let optionCodes: [String]?
    /// POST05 正文或选中 other 后的补充文字
    let textValue: String?
    let answeredAt: Date?
}

nonisolated struct SurveyOutcome: Codable {
    let formKey: String
    let formVersion: String
    let translationVersion: String
    let language: String
    let answers: [SurveyAnswer]
    /// 完全不填 = declined；有部分未答 = partial；全部有答 = complete
    let status: String
    let startedAt: Date?
    let submittedAt: Date?

    private func codes(_ qid: String) -> [String]? {
        answers.first { $0.questionID == qid && $0.state == .answered }?.optionCodes
    }

    // MARK: - 供端侧资格判定的派生字段（字典 §10：筛选先在本地完成）

    /// B01。`prefer_not` 与跳过都返回 nil——**不猜测**，资格判定会落到 pending
    var isAdult: Bool? {
        guard let c = codes("B01")?.first else { return nil }
        switch c {
        case "adult": return true
        case "minor": return false
        default: return nil          // prefer_not
        }
    }

    /// B02。ISO 3166-1 alpha-2；prefer_not 视为未提供
    var nationalities: Set<String>? {
        guard let c = codes("B02"), !c.contains("prefer_not") else { return nil }
        return c.isEmpty ? nil : Set(c)
    }

    /// B03，自报课程阶段，**不等同于考试水平**
    var courseStage: String? { codes("B03")?.first }
}
