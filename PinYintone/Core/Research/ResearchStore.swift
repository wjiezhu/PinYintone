import Combine
import CryptoKit
import Foundation

/// 研究状态与待传队列的**按账号**持久化（需求 R05 / R07 / R08）。
///
/// 两件事以前都没做到：
/// - **账号隔离**：状态存在全局 UserDefaults，退出登录换个人，上一位的同意、
///   研究编号、问卷计数全都还在。
/// - **队列落盘**：尝试与事件队列只在内存里，App 被杀就丢；问卷上传失败则直接吞掉。
///
/// 现在每个账号一个独立的存储域。当前没有登录账号时，存储域为空且**只读为空**——
/// 没有账号就没有研究状态，也不采集。
@MainActor
final class ResearchStore: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchStore()

    @Published private(set) var state = ResearchState()
    /// 当前账号的存储键；未登录为 nil
    private(set) var accountKey: String?

    private var defaults: UserDefaults?
    private var suiteName: String?

    private enum Key {
        static let state = "state"
        static func queue(_ name: String) -> String { "queue.\(name)" }
    }

    private init() {}

    // MARK: - 账号切换

    /// 切到某个账号的研究状态。`profile` 为 nil（未登录）或教师账号时没有研究状态。
    ///
    /// 上一个账号的状态与待传队列**留在它自己的存储域里**，不清除也不带走：
    /// 那是它在有效同意期间合法产生的数据，等它重新登录后还能补传。
    func activate(for profile: UserProfile?) {
        guard let profile, profile.role == .student else {
            activate(accountKey: nil)
            return
        }
        activate(accountKey: profile.appleUserID ?? profile.deviceID)
    }

    func activate(accountKey: String?) {
        self.accountKey = accountKey
        guard let accountKey else {
            defaults = nil
            suiteName = nil
            state = ResearchState()
            reloadQueues()
            return
        }
        let name = Self.suiteName(for: accountKey)
        suiteName = name
        defaults = UserDefaults(suiteName: name)
        if let data = defaults?.data(forKey: Key.state),
           let saved = try? Self.decoder.decode(ResearchState.self, from: data) {
            state = saved
        } else {
            state = ResearchState()
            migrateLegacyGlobalState()
        }
        reloadQueues()
    }

    /// 各队列各自持有内存副本；换账号后必须重新从该账号的存储域加载，
    /// 否则上一个账号的待传记录会被当成当前账号的发出去。
    private func reloadQueues() {
        ResearchAttemptLog.shared.reload()
        ResearchEventLog.shared.reload()
        AdviceRequestLog.shared.reload()
        ResearchRecordingQueue.shared.reload()
    }

    /// 研究开了新的一轮（新的 study_id）：上一轮的参与状态不再挡住新一轮的邀请。
    ///
    /// 只在上一轮的东西都已送达之后才翻篇——还有没传完的尝试、事件、问卷、录音或退出指令时
    /// 先不动，它们会按上一轮的身份补传完，下次刷新配置时再翻。
    func rollOverToNewStudyIfNeeded(_ studyID: String) {
        guard accountKey != nil else { return }
        let s = state
        guard s.participation != .notAsked, s.roundStudyID != studyID else { return }
        let drained = s.pendingWithdrawal == nil
            && ResearchAttemptLog.shared.pending.isEmpty
            && ResearchEventLog.shared.pending.isEmpty
            && AdviceRequestLog.shared.pending.isEmpty
            && ResearchRecordingQueue.shared.pending.isEmpty
            && SurveyCenter.recordsNeedingUpload(in: s).isEmpty
        guard drained else { return }
        update { $0 = ResearchState() }
        // 上一轮在首页关掉的研究邀请，新一轮重新出现一次
        UserDefaults.standard.removeObject(forKey: "pt_research_home_row_dismissed")
    }

    /// 本账号研究数据在本机的存储域名（录音文件也按它分目录）。未登录为 nil
    var storageDomain: String? { suiteName }

    /// 删除账号时抹掉该账号在本机的全部研究状态与队列。
    func purgeCurrentAccount() {
        ResearchRecordingQueue.shared.removeAll()
        if let suiteName { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        defaults?.removeObject(forKey: Key.state)
        activate(accountKey: nil)
    }

    /// 存储域名不含账号标识本身：Apple 标识不该出现在文件名里。
    private static func suiteName(for accountKey: String) -> String {
        let digest = SHA256.hash(data: Data(accountKey.utf8))
        return "pt.research." + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 状态读写

    /// 修改状态并落盘。没有账号时不做任何事。
    func update(_ mutate: (inout ResearchState) -> Void) {
        guard defaults != nil else { return }
        var next = state
        mutate(&next)
        guard next != state else { return }
        state = next
        if let data = try? Self.encoder.encode(next) {
            defaults?.set(data, forKey: Key.state)
        }
    }

    // MARK: - 队列

    func loadQueue<T: Decodable>(_ name: String, as type: T.Type = T.self) -> [T] {
        guard let data = defaults?.data(forKey: Key.queue(name)) else { return [] }
        return (try? Self.decoder.decode([T].self, from: data)) ?? []
    }

    func saveQueue<T: Encodable>(_ name: String, _ items: [T]) {
        guard let defaults else { return }
        if items.isEmpty {
            defaults.removeObject(forKey: Key.queue(name))
        } else if let data = try? Self.encoder.encode(items) {
            defaults.set(data, forKey: Key.queue(name))
        }
    }

    /// 被服务端明确拒收、不再重试的记录条数。不丢计数：调试与验收时要能看见。
    func addDeadLetters(_ count: Int, queue: String) {
        guard let defaults, count > 0 else { return }
        let key = "dead.\(queue)"
        defaults.set(defaults.integer(forKey: key) + count, forKey: key)
    }

    func deadLetterCount(queue: String) -> Int {
        defaults?.integer(forKey: "dead.\(queue)") ?? 0
    }

    // MARK: - 编解码

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()

    // MARK: - 旧版全局状态迁移

    /// 本次修复之前，研究状态存在全局 UserDefaults 里、不分账号。
    /// 升级后第一次登录的账号继承这份状态（它只可能属于这台设备上最近用的那个账号），
    /// 随后清掉全局键，不再让第二个账号看见。
    ///
    /// 迁移**不提升**状态：旧版里「已同意」而没有研究编号的，降为「已同意待纳入」；
    /// 旧版的资格只在内存里，这里无从得知，已纳入者按 eligible 处理
    /// （旧版的纳入门槛比现在更严，纳入过即说明当时判过合格）。
    private func migrateLegacyGlobalState() {
        let d = UserDefaults.standard
        guard let raw = d.string(forKey: Legacy.consentState) else { return }
        let participant = d.string(forKey: Legacy.participant)
        let manifest = d.string(forKey: Legacy.manifest)
        update { s in
            switch raw {
            case "granted":
                s.consentVersion = d.string(forKey: Legacy.consentVersion)
                s.consentLanguage = LocalizationManager.shared.language
                if let participant, let manifest {
                    s.participation = .enrolled
                    s.eligibility = "eligible"
                    s.participantID = participant
                    s.manifestID = manifest
                    s.studyID = d.string(forKey: Legacy.study)
                    s.windowStart = d.object(forKey: Legacy.windowStart) as? Date
                    s.windowEnd = d.object(forKey: Legacy.windowEnd) as? Date
                } else {
                    s.participation = .consentedPending
                }
            case "declined":  s.participation = .declined
            case "withdrawn": s.participation = .withdrawn
            default: break
            }
            s.qualifyingCount = d.integer(forKey: Legacy.counted)
            s.countedAttemptIDs = d.stringArray(forKey: Legacy.countedIDs) ?? []
        }
        Legacy.all.forEach { d.removeObject(forKey: $0) }
    }

    private enum Legacy {
        static let consentState = "pt_research_consent_state"
        static let consentVersion = "pt_research_consent_version"
        static let consentLanguage = "pt_research_consent_language"
        static let participant = "pt_research_participant_id"
        static let manifest = "pt_research_manifest_id"
        static let study = "pt_research_study_id"
        static let windowStart = "pt_research_window_start"
        static let windowEnd = "pt_research_window_end"
        static let counted = "pt_research_qualifying_attempts"
        static let countedIDs = "pt_research_counted_attempt_ids"
        static let all = [consentState, consentVersion, consentLanguage, participant,
                          manifest, study, counted, countedIDs,
                          "pt_research_post_invited", "pt_research_pre_invited",
                          "pt_research_first_attempt_started", "pt_research_invited"]
    }
}
