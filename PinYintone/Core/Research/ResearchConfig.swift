import Combine
import Foundation

/// 研究配置的本地缓存与**兼容性自检**（需求 R03）。
///
/// `manifestID` **由服务端下发，客户端不硬编码**：配置由研究者冻结，
/// 硬编码会在换配置时把数据归到旧配置下（字典 §3：不同配置不能直接混算分数）。
///
/// 取不到配置、配置过期、或配置绑定的材料与本机实际携带的不一致时，
/// 研究路径**关闭**——不邀请、不纳入。普通练习完全不受影响，
/// 学习者也不会看到任何配置或数据库层面的报错。
@MainActor
final class ResearchConfig: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchConfig()

    /// 可用于**新纳入**的配置。nil = 当前不开放参加研究。
    @Published private(set) var available: Manifest?

    nonisolated struct Manifest: Codable, Equatable {
        let manifestID: String
        let studyID: String
        let collectionStartAt: Date
        let collectionEndAt: Date
        let postTriggerCount: Int
        let consentVersion: String
        let rewardRuleVersion: String?
        let isTest: Bool
        /// 现场实测协议（与本机携带的协议核对过才保留；不一致时为 nil）
        var fieldProtocolVersion: String? = nil
        var fieldProtocol: APIClient.FieldProtocolSpec? = nil
        /// 配置是否接收录音
        var audioUpload: Bool = false

        var window: ResearchGate.CollectionWindow {
            .init(start: collectionStartAt, end: collectionEndAt)
        }
    }

    private static let cacheKey = "pt_research_available_manifest"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            available = m
        }
        dropIfExpired()
    }

    var manifestID: String? { available?.manifestID }

    /// 积分规则版本。**为空表示积分功能未上线**（本轮保持关闭）。
    var rewardRuleVersion: String? { available?.rewardRuleVersion }

    /// 使用后问卷的触发次数。配置不可用时用研究者已确认的默认值 5；
    /// 已纳入者离线时也要能正确计数。
    var postTriggerCount: Int { available?.postTriggerCount ?? 5 }

    /// 当前是否开放参加研究：有与本机匹配的配置，且此刻在其采集窗口内。
    func isOpen(now: Date = Date()) -> Bool {
        guard let available else { return false }
        return available.window.contains(now)
    }

    /// 已纳入的这位参与者此刻能不能做现场实测：正在采集、纳入所用的就是当前配置、
    /// 配置带了实测协议，且协议与本机携带的一致。
    func fieldSessionAvailable(now: Date = Date()) -> Bool {
        let state = ResearchStore.shared.state
        guard ResearchGate.shouldCollect(now: now),
              let m = available, m.manifestID == state.manifestID,
              m.fieldProtocol != nil else { return false }
        return true
    }

    /// 联网刷新。
    ///
    /// - 服务端明确回答「没有匹配的配置」（404）：清掉缓存，研究路径关闭。
    /// - 网络失败：保留缓存。离线不应让开放状态凭空消失，
    ///   但过期的缓存仍会被 `isOpen` 按时间挡住。
    /// - 下发的配置与本机材料不匹配：视同没有配置。
    func refresh() async {
        do {
            let m = try await APIClient.shared.fetchActiveManifest(
                appVersion: AppEnvironment.appVersion,
                build: AppEnvironment.buildNumber,
                test: AppEnvironment.isTestAccount)
            if let reason = Self.incompatibility(of: m) {
                #if DEBUG
                print("[ResearchConfig] 配置与本机材料不匹配，研究路径关闭：\(reason)")
                #endif
                store(nil)
            } else {
                // 协议对不上本机携带的那份：不提供现场实测，其余研究功能照常
                let protocolMatches = m.fieldProtocol.map {
                    FieldProtocol.bundled?.matches($0, version: m.fieldProtocolVersion) ?? false
                } ?? false
                store(Manifest(manifestID: m.manifestID, studyID: m.studyID,
                               collectionStartAt: m.collectionStartAt,
                               collectionEndAt: m.collectionEndAt,
                               postTriggerCount: m.postTriggerCount,
                               consentVersion: m.consentVersion,
                               rewardRuleVersion: m.rewardRuleVersion,
                               isTest: m.isTest ?? false,
                               fieldProtocolVersion: protocolMatches ? m.fieldProtocolVersion : nil,
                               fieldProtocol: protocolMatches ? m.fieldProtocol : nil,
                               audioUpload: m.audioUpload ?? false))
                ResearchStore.shared.rollOverToNewStudyIfNeeded(m.studyID)
                syncEnrolledWindow()
            }
        } catch let error as ResearchAPIError {
            if case .http(let status, _) = error, status == 404 { store(nil) }
        } catch {
            // 其它错误（解码失败等）：保守起见关闭研究路径
            store(nil)
        }
    }

    /// 下发的配置是否与本机**实际携带**的材料一致。返回不一致的原因；一致返回 nil。
    ///
    /// 配置绑定了同意文本、纳入规则、词库、问卷与译文的版本。任何一项对不上，
    /// 说明这台设备拿到的不是为它准备的配置——带着不匹配的材料去采集，
    /// 数据会被归到错误的版本名下。
    nonisolated static func incompatibility(of m: APIClient.ActiveManifest,
                                            consentVersions: Set<String> = ResearchConsent.supportedVersions,
                                            eligibilityVersion: String = ResearchEligibility.version,
                                            lexiconVersion: String? = ResearchLexicon.lexiconVersion,
                                            forms: [String: SurveyForm] = SurveyFormLoader.bundled,
                                            appVersion: String = AppEnvironment.appVersion,
                                            isTestClient: Bool = AppEnvironment.isTestAccount) -> String? {
        if m.collectionEndAt <= m.collectionStartAt { return "window" }
        if !consentVersions.contains(m.consentVersion) { return "consent_version" }
        // 收录音的配置必须配写明录音的同意文本，反之亦然（服务端冻结时也查过，这里再挡一次）
        if (m.audioUpload ?? false)
            != ResearchConsent.allowsAudioUpload(consentVersion: m.consentVersion) {
            return "audio_consent"
        }
        if let v = m.eligibilityVersion, v != eligibilityVersion { return "eligibility_version" }
        if let v = m.lexiconVersion, v != lexiconVersion { return "lexicon_version" }
        if let v = m.appVersion, v != appVersion { return "app_version" }
        if (m.isTest ?? false) && !isTestClient { return "test_manifest" }
        if let bound = m.surveyForms {
            for key in SurveyFormLoader.formKeys {
                guard let spec = bound[key], let form = forms[key] else { return "survey_form:\(key)" }
                if spec["form_version"] != form.formVersion
                    || spec["translation_version"] != form.translationVersion {
                    return "survey_form:\(key)"
                }
            }
        }
        return nil
    }

    /// 已纳入者：若下发的仍是其纳入所用的那份配置，同步窗口快照
    /// （研究者不会改已冻结的配置，这里只是让缓存与服务端保持一致）。
    private func syncEnrolledWindow() {
        guard let m = available else { return }
        let store = ResearchStore.shared
        guard store.state.participation == .enrolled,
              store.state.manifestID == m.manifestID else { return }
        store.update { s in
            s.windowStart = m.collectionStartAt
            s.windowEnd = m.collectionEndAt
            s.audioUpload = m.audioUpload
        }
    }

    private func store(_ m: Manifest?) {
        available = m
        if let m, let data = try? JSONEncoder().encode(m) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        }
    }

    private func dropIfExpired(now: Date = Date()) {
        if let available, now >= available.collectionEndAt { store(nil) }
    }

    #if DEBUG
    /// 仅供测试：直接设置可用配置
    func setAvailableForTesting(_ m: Manifest?) { store(m) }
    #endif
}

/// 构建与测试账户识别（需求 §7：测试数据必须 is_test=true，正式导出默认排除）。
nonisolated enum AppEnvironment {
    private static let testKey = "pt_is_test_account"

    static let appVersion: String =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    static let buildNumber: String =
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

    /// 开发构建一律是测试数据；正式构建只有显式置位才是。
    static var isTestAccount: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: testKey)
        #endif
    }
}
