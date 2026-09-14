import Foundation

/// 问卷上报。
///
/// **纳入成功之后才调用**：字典 §10 要求「背景筛选先在本地完成，
/// 符合条件后才上传背景实例」——未纳入就上传等于把不合格者的答案也收进研究库。
@MainActor
final class SurveyUploader {
    static let shared = SurveyUploader()
    private init() {}

    /// 上传一份问卷。失败不重试也不抛错——问卷不应阻断使用流程，
    /// 由下次进前台的 flush 或用户再次提交处理。
    func upload(_ outcome: SurveyOutcome) async {
        let id = ResearchIdentity.shared
        guard let pid = id.participantID, let mid = id.manifestID else { return }
        try? await APIClient.shared.uploadSurvey(participantID: pid,
                                                 manifestID: mid,
                                                 outcome: outcome)
    }
}
