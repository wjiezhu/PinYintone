import Foundation

/// 纳入研究的调用封装。
///
/// 分成独立类型而不是塞进视图，是为了让「同意 → 纳入 → 存身份」这条
/// 顺序可被测试，也让失败回滚的责任明确落在一处。
@MainActor
enum ResearchEnrollment {

    /// 当前配置编号，由服务端下发并缓存在 `ResearchConfig`。
    /// 未配置则不纳入，不猜默认值——manifest 决定评分/词库/问卷版本，
    /// 猜错会把数据归到错误的配置下。
    static var manifestID: String? { ResearchConfig.shared.manifestID }

    enum EnrollError: Error {
        case noManifestConfigured
        case noAccount
    }

    /// 用当前业务账号纳入研究。成功后本地持有研究编号。
    static func enrollCurrentUser(consentLanguage: String) async throws {
        guard let manifestID else { throw EnrollError.noManifestConfigured }
        guard let profile = UserManager.shared.profile else { throw EnrollError.noAccount }

        let resp = try await APIClient.shared.enrollResearch(
            internalUserID: profile.deviceID,
            manifestID: manifestID,
            consentVersion: ResearchConsent.textVersion,
            consentLanguage: consentLanguage,
            consentOccurredAt: Date(),
            isTest: AppEnvironment.isTestAccount)
        ResearchIdentity.shared.store(participantID: resp.participantID,
                                      manifestID: manifestID,
                                      studyID: resp.studyID)
    }

    /// 撤回：服务端记一条 withdrawn，端侧立即停采并清空待传队列。
    static func withdraw(language: String) async {
        let id = ResearchIdentity.shared
        if let pid = id.participantID {
            try? await APIClient.shared.withdrawResearch(
                participantID: pid,
                consentVersion: ResearchConsent.textVersion,
                consentLanguage: language,
                occurredAt: Date())
        }
        // 即便联网失败也要在端侧停止采集——字典 §5：
        // 「撤回在端侧立即停止研究采集并清除待上传研究队列」
        ResearchConsent.shared.withdraw()
        ResearchEventLog.shared.clearPendingOnWithdrawal()
        ResearchAttemptLog.shared.clearPendingOnWithdrawal()
        id.clearOnWithdrawal()
    }
}

/// 测试账户识别（需求 §8：开发测试账户必须可识别并排除）。
enum AppEnvironment {
    private static let key = "pt_is_test_account"
    /// 由内部构建或调试开关置位；正式用户恒为 false
    static var isTestAccount: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: key)
        #endif
    }
}
