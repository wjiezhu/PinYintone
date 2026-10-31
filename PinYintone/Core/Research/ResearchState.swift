import Foundation

/// 一个账号在本机的全部研究状态（需求 R02 / R05 / R08）。
///
/// 整份状态**按账号保存**：换账号时研究身份、同意、问卷草稿、计数都不带过去。
/// 此前这些散在全局 UserDefaults 里，退出登录换个人，上一个人的同意状态
/// 和研究编号还在，新账号的练习会被记到别人名下。
nonisolated struct ResearchState: Codable, Equatable {

    /// 参与状态。四种「已同意之后」的情形必须分开管（需求 R02）：
    /// 本地同意**不等于**已参加——服务端确认纳入之前不产生任何研究日志。
    enum Participation: String, Codable {
        /// 尚未询问
        case notAsked
        /// 明确拒绝。本地记住，不反复弹出；用户主动重新进入时才再次询问
        case declined
        /// 已同意，但尚未纳入：背景表没答完，或纳入请求还没成功。可从设置恢复
        case consentedPending
        /// 已同意，但端侧判定不符合条件或无法判定。不纳入，照常使用
        case ineligible
        /// 服务端已确认纳入（「已参与」）。背景表是否已送达见 `backgroundAcked`
        case enrolled
        /// 已退出研究
        case withdrawn
    }

    var participation: Participation = .notAsked

    // MARK: 同意（用户**实际看到**的版本与界面语言，随纳入上报）
    var consentVersion: String?
    var consentLanguage: String?
    var consentAt: Date?

    // MARK: 端侧资格判定
    /// eligible / pending / excluded:<原因>。持久化——此前只放内存，
    /// 结果是 App 一重启资格就变回 pending，已纳入的人此后再不产生研究数据。
    var eligibility: String?

    // MARK: 研究身份（服务端发回，本机只缓存）
    var participantID: String?
    var manifestID: String?
    var studyID: String?
    /// 纳入所用配置的采集窗口快照。离线时据此判断是否仍在采集期内。
    var windowStart: Date?
    var windowEnd: Date?

    /// 已同意、已判合格、但纳入请求还没成功时暂存的背景答卷。
    /// **只存在本机**；纳入成功后进入问卷上传队列，判不合格或拒绝后即清除。
    var pendingBackground: SurveyOutcome?

    /// 背景表作答中的草稿（纳入之前，背景表还不是研究库里的问卷实例）。
    /// 只在本机；提交判定、拒绝或退出后清除。
    var backgroundDraft: SurveyDraft?
    var backgroundStartedAt: Date?
    /// 背景表开始作答时的界面语言，恢复草稿时仍用它
    var backgroundLanguage: String?

    /// 离线退出时留下的最小指令。联网后**先**同步它，之后不再上传任何研究内容。
    var pendingWithdrawal: PendingWithdrawal?

    // MARK: 问卷
    /// 按 formKey 保存的问卷实例。每份问卷只有一个实例，从邀请到提交始终是它。
    var surveys: [String: SurveyRecord] = [:]
    /// 累计合格练习次数与已计入的尝试编号（按 attempt_id 去重）
    var qualifyingCount = 0
    var countedAttemptIDs: [String] = []
    /// 新版中首次开始练习的时间。用于判定前置问卷是「练习前」还是 late_pre——
    /// 以**完成时间**相对它的先后为准，与何时上传无关。
    var firstPracticeStartedAt: Date?
    /// 首页那条「继续填写问卷」提示是否被用户关掉了（问卷本身仍可从设置进入）
    var surveyBannerDismissed = false
    /// 已达到使用后问卷的邀请条件，但还没展示给用户（等他结束当前反馈再邀请）。
    /// 落盘：达到条件后 App 被杀，下次进练习页仍会邀请，不需要再练。
    var postInvitationDue = false
    /// 使用后问卷的触发次数，纳入时随配置记下
    var postTriggerCount: Int?

    /// 这份参与状态属于哪一轮研究（study_id）。同意时记下。
    /// 研究换了新的一轮（新 study_id），上一轮的「已参与 / 已退出 / 未纳入」不该挡住新一轮的邀请。
    /// 升级前留下的状态没有这一项，一律视为第一轮。
    var roundStudyID: String?
    /// 纳入所用配置是否接收录音（纳入时与配置刷新时记下）。离线或配置下线后据此决定能否补传录音
    var audioUpload: Bool?
    /// 刚用 Apple 账号登录、还没弹过参加研究的说明。弹一次就清掉；关掉不算同意
    var signupConsentDue = false

    struct PendingWithdrawal: Codable, Equatable {
        let participantID: String
        let consentVersion: String
        let language: String
        let occurredAt: Date
    }

    // MARK: - 派生

    var eligibilityOutcome: ResearchEligibility.Outcome {
        guard let eligibility else { return .pending }
        if eligibility == "eligible" { return .eligible }
        if eligibility.hasPrefix("excluded:"),
           let reason = ResearchEligibility.Exclusion(
               rawValue: String(eligibility.dropFirst("excluded:".count))) {
            return .excluded(reason)
        }
        return .pending
    }

    var window: ResearchGate.CollectionWindow? {
        guard let windowStart, let windowEnd else { return nil }
        return .init(start: windowStart, end: windowEnd)
    }

    /// 是否持有可用于上传的研究身份
    var hasIdentity: Bool { participantID != nil && manifestID != nil }

    /// 背景表是否已被**服务端确认**收到。未确认前尝试与事件先留在本机
    /// （上传顺序：身份及背景确认 → 尝试 → 关联事件）。
    var backgroundAcked: Bool {
        surveys["background_v1"]?.isSynced == true
    }
}

/// 一份问卷实例在本机的状态。
///
/// 邀请发生时就把快照定下来——邀请时间、当时的合格次数、当时的界面语言、
/// 表单与译文版本——之后重试上传**不得**用上传时的当前值替代（需求 R05 末）。
nonisolated struct SurveyRecord: Codable, Equatable, Identifiable {
    var id: UUID { instanceID }

    enum Status: String, Codable {
        /// 已邀请，用户还没做选择
        case invited
        /// 用户选了「稍后填写」（或中途离开），可恢复
        case deferred
        /// 用户明确选了「不填写」
        case declined
        /// 用户主动提交，但有题未答
        case partial
        /// 全部作答并提交
        case complete

        /// 用户已主动结束这份问卷。之后不再邀请、不再修改。
        var isFinal: Bool { self == .declined || self == .partial || self == .complete }
        /// 已提交了答案（区别于「明确不填写」）
        var isSubmitted: Bool { self == .partial || self == .complete }
    }

    /// 稳定的实例编号，也是上传的幂等键。从邀请到最终提交始终不变。
    let instanceID: UUID
    let formKey: String
    let formVersion: String
    let translationVersion: String
    /// 邀请时用户实际看到的界面语言。恢复草稿时仍用它显示，不随当前语言漂移。
    let language: String
    let invitedAt: Date
    let qualifyingAttemptsAtInvite: Int

    var status: Status
    var startedAt: Date?
    var submittedAt: Date?
    /// 最终提交时按**发生时间**定下的时间定位；提交前为 nil
    var timingClass: String?
    /// 最终答案。上传成功前一直留在本机。
    var answers: [SurveyAnswer] = []
    /// 作答中的草稿。返回、切后台、重启都不丢；提交或拒绝后清除。
    var draft: SurveyDraft?
    /// 服务端已确认到哪个状态。与 `status` 不同即表示还有待上传的变更。
    var syncedStatus: Status?
    /// 服务端明确拒收（例如窗口已关闭）。不再重试，也不显示为「已提交」。
    var rejectedReason: String?

    var isSynced: Bool { syncedStatus == status }
    /// 还能继续填：已邀请或稍后填写，且未被服务端拒收
    var isResumable: Bool { !status.isFinal && rejectedReason == nil }
}

/// 问卷作答草稿。
nonisolated struct SurveyDraft: Codable, Equatable {
    var index = 0
    var selections: [String: [String]] = [:]
    var texts: [String: String] = [:]
    var skipped: [String] = []
    var answeredAt: [String: Date] = [:]
}
