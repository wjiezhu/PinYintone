import Combine
import Foundation

/// 研究授权状态与本地门禁（需求 §2、字段字典 §5）。
///
/// 核心约束：
/// - 研究授权与普通注册**分开**。注册、Apple 登录、填写背景表
///   **都不构成**研究同意（字典 §1）。
/// - **不默认勾选**，必须用户主动选择。
/// - 不同意仍可使用全部正常功能，只是不产生研究记录。
/// - 同意/撤回**追加记录**，不覆盖历史。
/// - 撤回后**端侧立即停止采集并清空待上传研究队列**，不等服务端确认。
@MainActor
final class ResearchConsent: ObservableObject {
    static let shared = ResearchConsent()

    /// 知情同意文本版本。
    ///
    /// ⚠ **文本本身尚未纳入本仓库**：四语知情同意说明见研究方的
    /// 《新版研究_四语知情同意说明_待审稿_v1》，该稿待审校。
    /// 在正式文本落地并审定前，本版本号只能用于联调，
    /// **不得开启正式采集**（字典 §16：待定项未完成则相应采集不开启）。
    static let textVersion = "consent-1.0-unpublished"

    enum State: String {
        case notAsked        // 尚未询问
        case granted         // 已同意
        case declined        // 明确拒绝——本地记住，避免反复打扰
        case withdrawn       // 曾同意后撤回
    }

    @Published private(set) var state: State
    /// 用户**实际看到**的同意文本版本与语言，随事件上报
    @Published private(set) var grantedVersion: String?
    @Published private(set) var grantedLanguage: String?

    private static let stateKey = "pt_research_consent_state"
    private static let versionKey = "pt_research_consent_version"
    private static let languageKey = "pt_research_consent_language"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.stateKey)
        state = raw.flatMap(State.init(rawValue:)) ?? .notAsked
        grantedVersion = UserDefaults.standard.string(forKey: Self.versionKey)
        grantedLanguage = UserDefaults.standard.string(forKey: Self.languageKey)
    }

    /// 是否允许产生研究记录。**所有研究埋点写入前都必须过这一关。**
    /// 这是端侧门禁：字典禁止「先全量收集、导出时再过滤」。
    var allowsResearchCollection: Bool { state == .granted }

    /// 用户主动同意。记录其实际看到的文本版本与语言。
    func grant(textVersion: String, language: String) {
        state = .granted
        grantedVersion = textVersion
        grantedLanguage = language
        persist()
    }

    /// 明确拒绝。本地记住即可，**不创建研究参与者**（字典 §5）。
    func decline() {
        state = .declined
        persist()
    }

    /// 撤回同意。
    ///
    /// 端侧立即停止采集并清空待上传队列；服务端确认后停止接收。
    /// ⚠ 撤回**不等于**删除账号或业务学习记录，也不自动删除既有研究资料——
    /// 既有资料的处理方式必须与知情同意书的表述一致，
    /// 该策略尚待研究方核对后冻结（字典 §5、docs/V2_DECISIONS.md 待确认 C）。
    func withdraw() {
        state = .withdrawn
        persist()
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(state.rawValue, forKey: Self.stateKey)
        d.set(grantedVersion, forKey: Self.versionKey)
        d.set(grantedLanguage, forKey: Self.languageKey)
    }
}
