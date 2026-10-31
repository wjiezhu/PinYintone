import Foundation

/// 研究同意的文本版本与本地操作（需求 R02 / R08、字段字典 §5）。
///
/// 核心约束：
/// - 研究授权与普通注册**分开**。注册、Apple 登录、填写背景表
///   **都不构成**研究同意（字典 §1）。
/// - **不默认勾选**，必须用户主动选择。
/// - 不同意仍可使用全部正常功能，只是不产生研究记录。
/// - 本地同意**不等于**已参加：服务端确认纳入之前，参与状态是
///   「已同意待纳入」，不产生任何研究日志。
///
/// 状态本身存在 `ResearchStore`（按账号隔离），这里只放版本号与状态迁移。
@MainActor
enum ResearchConsent {

    /// 本构建携带的知情同意文本。**文案有任何改动都必须换新版本号**，并重新冻结研究配置。
    ///
    /// 历史：`consent-1.0`（研究者 2026-10-14 审定，第一轮自然使用研究）不再随 App 携带。
    ///
    /// - `consent-1.1`：现场实测轮。说明前测 → 训练 → 后测，**录音不上传**。
    /// - `consent-2.0`：同上，另写明**上传录音**、退出即删除录音。
    ///   只有开了录音上传的配置才会下发这一版（种子脚本强制两者一致）。
    ///
    /// 两版都是开发方起草、待研究者与导师审定的稿子；审定记在
    /// `backend/research_materials_approval.json`，未审定只能冻结成测试配置。
    nonisolated enum Text: String, CaseIterable {
        case fieldSession = "consent-1.1"
        case fieldSessionWithAudio = "consent-2.0"

        /// 这一版是否写明了上传录音
        var includesAudioUpload: Bool { self == .fieldSessionWithAudio }

        /// 依次显示的段落（标题键, 正文键）
        var sections: [(title: String, body: String)] {
            [("consent_purpose_title", "consent_purpose_body"),
             ("consent_data_title", includesAudioUpload ? "consent_data_body_audio"
                                                         : "consent_data_body"),
             ("consent_use_title", "consent_use_body"),
             ("consent_benefit_title", "consent_benefit_body"),
             ("consent_withdraw_title", includesAudioUpload ? "consent_withdraw_body_audio"
                                                             : "consent_withdraw_body")]
        }
    }

    /// 参与者可以联系的微信号（汉语问题、学习资料）
    nonisolated static let wechatID = "herecomes_zhuozhuo"

    nonisolated static let supportedVersions = Set(Text.allCases.map(\.rawValue))

    /// 现在应当给用户看的那一版：配置下发的版本（本构建携带才算），否则不含录音的那一版。
    /// 研究入口只在配置可用时出现，所以实际看到的总是配置要求的那一版。
    static var current: Text {
        ResearchConfig.shared.available.flatMap { Text(rawValue: $0.consentVersion) }
            ?? .fieldSession
    }

    /// 当前应显示的文本版本号
    static var textVersion: String { current.rawValue }

    /// 某个已同意的版本是否包含上传录音。只认本构建携带且写明了录音的版本
    nonisolated static func allowsAudioUpload(consentVersion: String?) -> Bool {
        consentVersion.flatMap(Text.init(rawValue:))?.includesAudioUpload ?? false
    }

    /// 用户主动同意。记录其**实际看到**的文本版本与界面语言。
    ///
    /// 语言取 App 内选择的语言，不是 `Locale.current`——后者是系统区域
    /// （如 en_US、fr_MA），与用户在 App 里看到的同意文本用什么语言无关。
    static func grant(_ text: Text? = nil, now: Date = Date()) {
        let shown = text ?? current
        ResearchStore.shared.update { s in
            s.participation = .consentedPending
            s.roundStudyID = ResearchConfig.shared.available?.studyID
            s.consentVersion = shown.rawValue
            s.consentLanguage = LocalizationManager.shared.language
            s.consentAt = now
            s.eligibility = nil
            s.pendingBackground = nil
        }
    }

    /// 明确拒绝。本地记住即可，**不创建研究参与者**（字典 §5）。
    /// 之后不自动再问；用户从设置里主动进入时才再次询问。
    static func decline() {
        ResearchStore.shared.update { s in
            s.participation = .declined
            // 记下是哪一轮拒绝的：不记的话下次刷新配置就被当成「上一轮」翻篇，邀请又冒出来
            s.roundStudyID = ResearchConfig.shared.available?.studyID
            s.consentVersion = nil
            s.consentLanguage = nil
            s.consentAt = nil
            s.eligibility = nil
            s.pendingBackground = nil
            s.backgroundDraft = nil
            s.backgroundStartedAt = nil
            s.backgroundLanguage = nil
            s.surveys["background_v1"] = nil
        }
    }

    /// 是否可以向用户展示研究邀请（自动或主动）。
    /// 已参与、已退出、已判不符合者不再邀请。
    nonisolated static func canOfferInvitation(_ state: ResearchState) -> Bool {
        switch state.participation {
        case .notAsked, .declined, .consentedPending: return true
        case .ineligible, .enrolled, .withdrawn: return false
        }
    }

    /// 重新开始参加流程。只用于「关键题当时没答、所以没法判定」的人主动回来重填——
    /// 已明确判为不符合的（未成年、非目标国籍、课程阶段不符）不走这里。
    static func restart() {
        ResearchStore.shared.update { s in
            guard s.participation == .ineligible, s.eligibility == "pending" else { return }
            s.participation = .notAsked
            s.eligibility = nil
            s.consentVersion = nil
            s.consentLanguage = nil
            s.consentAt = nil
        }
    }
}
