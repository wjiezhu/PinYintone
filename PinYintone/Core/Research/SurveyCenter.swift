import Foundation

/// 问卷的邀请、草稿、提交与计数（需求 R05、字典 §10）。
///
/// 一份问卷从头到尾是**同一个实例**：邀请时生成编号并拍下快照，之后
/// 「稍后填写」「继续填写」「提交」「上传重试」都作用在这一个实例上，
/// 不会因为重试多出一份，也不会改掉邀请时间。
///
/// 合格练习的计数口径来自研究者已确认的定义，四条都容易做错：
/// - **只算「分析成功且结果已实际显示」的固定词条练习**。
/// - **不要求评分通过**。没通过照样计次。
/// - **同词重录可累计**，不要求 5 个不同词。
/// - **自由文本、自测、技术失败不计入**。
/// 按 `attempt_id` 去重：同一次练习的结果重复渲染（旋转屏幕、返回再进）不重复计次。
@MainActor
enum SurveyCenter {

    static let backgroundKey = "background_v1"
    static let preKey = "tone_needs_v1"
    static let postKey = "usability_short_v1"

    private static var store: ResearchStore { .shared }

    // MARK: - 练习起点与合格计数

    /// 记下新版中首次开始练习的时间（只记第一次）。
    ///
    /// 这是前置问卷时间定位的基准，对**所有已登录账号**都记，不限研究参与者——
    /// 先练习、后参加研究的人，其前置问卷就应当是 late_pre。
    static func markPracticeStarted(now: Date = Date()) {
        guard store.state.firstPracticeStartedAt == nil else { return }
        store.update { $0.firstPracticeStartedAt = now }
    }

    static var qualifyingCount: Int { store.state.qualifyingCount }

    /// 使用后问卷的触发次数。纳入时随身份一起记下，离线也能正确计数。
    static var threshold: Int { store.state.postTriggerCount ?? ResearchConfig.shared.postTriggerCount }

    /// 记一次合格练习。返回是否**恰好**在本次达到邀请条件。
    ///
    /// 达到条件只是把「该邀请了」记下来（落盘），**不在这里弹问卷**：
    /// 用户这时正在看刚出来的反馈，可能还要回听。等他结束这一步再邀请
    /// （见 `consumePostInvitationIfDue`）。
    @discardableResult
    static func recordQualifyingAttempt(_ attemptID: UUID,
                                        taskType: ResearchAttemptRecord.TaskType,
                                        resultDisplayed: Bool,
                                        now: Date = Date()) -> Bool {
        // 自由文本与自测不计入；结果未显示不计入；不在采集中的练习不是研究数据
        guard taskType == .fixedWord, resultDisplayed else { return false }
        guard ResearchGate.shouldCollect(now: now) else { return false }
        let key = attemptID.uuidString
        guard !store.state.countedAttemptIDs.contains(key) else { return false }

        var reached = false
        let limit = threshold
        store.update { s in
            s.countedAttemptIDs.append(key)
            s.qualifyingCount += 1
            // 只自动邀请一次：已有使用后问卷实例（不论什么状态）就不再触发
            if s.qualifyingCount >= limit, s.surveys[postKey] == nil, !s.postInvitationDue {
                s.postInvitationDue = true
                reached = true
            }
        }
        return reached
    }

    /// 是否有一份使用后问卷的邀请在等着展示
    static var isPostInvitationDue: Bool { store.state.postInvitationDue }

    /// 用户结束了当前这次反馈（换词、再练、离开页面）——现在可以邀请了。
    /// 生成邀请实例并返回；没有待展示的邀请时返回 nil。
    static func consumePostInvitationIfDue(now: Date = Date()) -> SurveyRecord? {
        guard store.state.postInvitationDue else { return nil }
        let record = invite(postKey, now: now)
        store.update { $0.postInvitationDue = false }
        return record
    }

    // MARK: - 邀请

    /// 为某份问卷建立实例（已存在则原样返回——同一份问卷不建第二个实例）。
    ///
    /// 邀请是新的研究数据，须在采集中；窗口关闭后不再发出新邀请。
    /// 快照在此刻定下：时间、当时的合格次数、当时的界面语言、表单与译文版本。
    @discardableResult
    static func invite(_ formKey: String, now: Date = Date()) -> SurveyRecord? {
        if let existing = store.state.surveys[formKey] { return existing }
        guard ResearchGate.shouldCollect(now: now),
              let form = SurveyFormLoader.bundled[formKey] else { return nil }
        let record = SurveyRecord(
            instanceID: UUID(),
            formKey: formKey,
            formVersion: form.formVersion,
            translationVersion: form.translationVersion,
            language: LocalizationManager.shared.language,
            invitedAt: now,
            // 背景与前置问卷邀请时合格次数为 0，不事后用新增次数覆盖（字典 §10）
            qualifyingAttemptsAtInvite: formKey == postKey ? store.state.qualifyingCount : 0,
            status: .invited)
        store.update { s in
            s.surveys[formKey] = record
            s.surveyBannerDismissed = false
        }
        ResearchUploader.shared.scheduleFlush()
        return record
    }

    static func record(_ formKey: String) -> SurveyRecord? { store.state.surveys[formKey] }

    /// 可以继续填写的问卷（已邀请或稍后填写）。背景表不在此列——它属于纳入流程。
    static func resumable(in state: ResearchState) -> [SurveyRecord] {
        [preKey, postKey].compactMap { state.surveys[$0] }.filter(\.isResumable)
    }

    // MARK: - 作答

    /// 保存草稿。每次作答变化都调用：返回、切后台、重启都不丢。
    static func saveDraft(_ formKey: String, _ draft: SurveyDraft, now: Date = Date()) {
        store.update { s in
            guard var r = s.surveys[formKey], !r.status.isFinal else { return }
            r.draft = draft
            r.startedAt = r.startedAt ?? now
            s.surveys[formKey] = r
        }
    }

    /// 「稍后填写」。保留草稿；之后可从首页或设置恢复，不需要重新达到次数。
    static func deferSurvey(_ formKey: String) {
        store.update { s in
            guard var r = s.surveys[formKey], !r.status.isFinal else { return }
            r.status = .deferred
            s.surveys[formKey] = r
        }
        ResearchUploader.shared.scheduleFlush()
    }

    /// 「不填写」。明确拒绝——与「稍后填写」和「跳过某题」都不是一回事。
    static func decline(_ formKey: String, now: Date = Date()) {
        store.update { s in
            guard var r = s.surveys[formKey], !r.status.isFinal else { return }
            r.status = .declined
            r.submittedAt = now
            r.timingClass = timingClass(for: formKey, completedAt: now, state: s)
            r.answers = []
            r.draft = nil
            s.surveys[formKey] = r
        }
        ResearchUploader.shared.scheduleFlush()
    }

    /// 提交。答案先落在本机，由上传队列可靠送达；服务端确认前**不算已提交**。
    static func submit(_ formKey: String, answers: [SurveyAnswer], now: Date = Date()) {
        store.update { s in
            guard var r = s.surveys[formKey], !r.status.isFinal else { return }
            r.status = status(for: answers)
            r.submittedAt = now
            r.startedAt = r.startedAt ?? now
            r.timingClass = timingClass(for: formKey, completedAt: now, state: s)
            r.answers = answers
            r.draft = nil
            s.surveys[formKey] = r
        }
        ResearchUploader.shared.scheduleFlush()
    }

    /// 全部有答 = complete；有题未答或跳过 = partial；一题都没答 = declined
    nonisolated static func status(for answers: [SurveyAnswer]) -> SurveyRecord.Status {
        let anyAnswered = answers.contains { $0.state == .answered }
        let allAnswered = !answers.isEmpty && answers.allSatisfy { $0.state == .answered }
        return !anyAnswered ? .declined : (allAnswered ? .complete : .partial)
    }

    /// 问卷的时间定位（字典 §10）。**只看发生时间**：
    /// 前置问卷在首次练习开始之前完成的是练习前调查；之后才完成的是 late_pre。
    /// 何时上传、何时到达服务端都不改变这个分类。
    nonisolated static func timingClass(for formKey: String, completedAt: Date,
                                        state: ResearchState) -> String {
        switch formKey {
        case backgroundKey: return "background"
        case postKey: return "after_practice"
        default:
            if let first = state.firstPracticeStartedAt, first <= completedAt {
                return "late_pre"
            }
            return "before_first_attempt"
        }
    }

    // MARK: - 上传状态

    /// 有待上传变更的问卷，背景表排最前（它是服务端判定资格的依据）。
    static func recordsNeedingUpload(in state: ResearchState) -> [SurveyRecord] {
        [backgroundKey, preKey, postKey]
            .compactMap { state.surveys[$0] }
            .filter { !$0.isSynced && $0.rejectedReason == nil }
    }

    /// 上传得到服务端确认后对账。`sent` 是这次发出去的状态，`server` 是服务端此刻保存的状态。
    ///
    /// - 两者一致：这一状态已送达。
    /// - 服务端已是**最终状态**而本机不是（同一账号在另一台设备上已经填完）：
    ///   以服务端为准，本机不再邀请、不再让人重填一遍。
    /// - 其余情况（服务端停在一个不低于本机的非最终状态）：本机这次的内容已送达。
    ///
    /// 用户在上传途中又改了状态（比如刚点了提交）时，本机状态已不等于 `sent`，
    /// 这里只记「`sent` 已送达」，新状态仍是待传。
    static func reconcile(_ formKey: String, sent: SurveyRecord.Status,
                          server: SurveyRecord.Status?) {
        store.update { s in
            guard var r = s.surveys[formKey] else { return }
            if let server, server.isFinal, !r.status.isFinal {
                r.status = server
                r.syncedStatus = server
                r.draft = nil
            } else {
                r.syncedStatus = sent
            }
            s.surveys[formKey] = r
        }
    }

    static func markRejected(_ formKey: String, reason: String) {
        store.update { s in
            guard var r = s.surveys[formKey] else { return }
            r.rejectedReason = reason
            s.surveys[formKey] = r
        }
    }

    /// 首页那条提示被用户关掉。问卷本身仍可从设置进入。
    static func dismissBanner() {
        store.update { $0.surveyBannerDismissed = true }
    }

    /// 退出研究时清空全部问卷状态与计数
    static func reset() {
        store.update { s in
            s.surveys = [:]
            s.qualifyingCount = 0
            s.countedAttemptIDs = []
            s.postInvitationDue = false
            s.surveyBannerDismissed = false
        }
    }
}

/// 学习者看到的问卷状态。**服务端确认后才是「已提交」**——
/// 只存在本机的，如实说「已保存，等待联网提交」。
nonisolated enum SurveyDisplayStatus: Equatable {
    case invited, deferred, declined
    case savedWaitingForNetwork
    case submitted
    case notAccepted

    init(_ r: SurveyRecord) {
        if r.rejectedReason != nil { self = .notAccepted; return }
        switch r.status {
        case .invited: self = .invited
        case .deferred: self = .deferred
        case .declined: self = .declined
        case .partial, .complete: self = r.isSynced ? .submitted : .savedWaitingForNetwork
        }
    }

    var localizationKey: String {
        switch self {
        case .invited: return "survey_status_invited"
        case .deferred: return "survey_status_deferred"
        case .declined: return "survey_status_declined"
        case .savedWaitingForNetwork: return "survey_status_saved_pending"
        case .submitted: return "survey_status_submitted"
        case .notAccepted: return "survey_status_not_accepted"
        }
    }
}
