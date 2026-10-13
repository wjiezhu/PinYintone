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

    /// 知情同意文本版本。
    ///
    /// ⚠ **文本尚未审定**：四语知情同意说明见研究方的
    /// 《新版研究_四语知情同意说明_待审稿_v1》。在正式文本落地并审定前，
    /// 本版本号只能用于联调——服务端的配置冻结脚本会拒绝用带
    /// `unpublished` 的版本冻结正式配置，所以**现在开不了正式采集**。
    /// 审定后须改这里的版本号与四语文案，并发新构建。
    nonisolated static let textVersion = "consent-1.0-unpublished"

    /// 用户主动同意。记录其**实际看到**的文本版本与界面语言。
    ///
    /// 语言取 App 内选择的语言，不是 `Locale.current`——后者是系统区域
    /// （如 en_US、fr_MA），与用户在 App 里看到的同意文本用什么语言无关。
    static func grant(now: Date = Date()) {
        ResearchStore.shared.update { s in
            s.participation = .consentedPending
            s.consentVersion = textVersion
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
