import Foundation

/// 参加与退出研究的状态迁移（需求 R01 / R02 / R08）。
///
/// 顺序不可调换，每一步都有出处：
/// 1. **先有业务账号**。没有账号就不进入研究流程——此前研究邀请排在登录之前，
///    纳入接口拿到的是空账号。
/// 2. **同意**。只记在本机，状态是「已同意待纳入」，**不等于已参加**。
/// 3. **背景表**，端侧判资格。不符合或关键题没答的人到此为止：
///    不纳入、不上传任何东西，背景答案当场清掉，照常使用 App。
/// 4. **服务端纳入确认**。成功后才是「已参与」，才开始产生研究日志。
///    失败（断网、超时）不回滚同意、不丢背景答案——保留原卷与原始时间，
///    可以重试，也可以先去练习，稍后从设置里回来继续。
/// 5. **背景表可靠提交**，走问卷上传队列。
/// 6. **首次练习前问卷邀请**。
@MainActor
enum ResearchEnrollment {

    enum EnrollError: Error, Equatable {
        /// 当前不开放参加（没有匹配的配置、不在采集窗口内）
        case notOpen
        /// 还没有业务账号
        case noAccount
        /// 流程状态不对（没同意、没有待提交的背景表）
        case notReady
        /// 网络问题，可重试
        case network
        /// 服务端明确不接受（已退出过、窗口已关等），重试无用
        case refused(String)
    }

    private static var store: ResearchStore { .shared }

    /// 研究入口此刻是否应当对这位用户可见。
    /// 需要：已登录的学生账号、当前有匹配且在窗口内的配置、状态允许邀请。
    static func canJoinNow(now: Date = Date()) -> Bool {
        guard store.accountKey != nil else { return false }
        guard ResearchConfig.shared.isOpen(now: now) else { return false }
        return ResearchConsent.canOfferInvitation(store.state)
    }

    /// 背景表答完。端侧判资格；合格则去服务端纳入。
    ///
    /// - Returns: 资格判定结果。`.eligible` 表示已成功纳入。
    /// - Throws: 仅在**已判合格但纳入没成功**时抛错。此时答卷已保存，可调 `retryEnrollment`。
    @discardableResult
    static func submitBackground(_ outcome: SurveyOutcome) async throws -> ResearchEligibility.Outcome {
        guard store.state.participation == .consentedPending else { throw EnrollError.notReady }
        let eligibility = ResearchEligibility.evaluate(background: outcome, consentGranted: true)

        guard eligibility == .eligible else {
            // 不符合条件，或关键题没答所以无法判定：不纳入，不猜。
            // 背景答案只在端侧用于这一次判定，用完即清，不进研究库。
            store.update { s in
                s.participation = .ineligible
                s.eligibility = eligibility.storageValue
                s.pendingBackground = nil
                s.backgroundDraft = nil
                s.backgroundStartedAt = nil
                s.backgroundLanguage = nil
                s.surveys[SurveyCenter.backgroundKey] = nil
            }
            return eligibility
        }

        // 合格：先把答卷连同原始时间存下来，再去纳入。纳入失败也不会丢。
        store.update { s in
            s.eligibility = eligibility.storageValue
            s.pendingBackground = outcome
        }
        try await enroll()
        return .eligible
    }

    /// 纳入请求之前失败过，现在重试。服务端幂等：重试不会多出一位参与者。
    static func retryEnrollment() async throws {
        guard store.state.participation == .consentedPending,
              store.state.eligibilityOutcome == .eligible,
              store.state.pendingBackground != nil else { throw EnrollError.notReady }
        try await enroll()
    }

    /// 是否处在「已判合格、等待纳入成功」的状态（界面据此显示重试入口）
    static var isAwaitingEnrollment: Bool {
        store.state.participation == .consentedPending
            && store.state.eligibilityOutcome == .eligible
            && store.state.pendingBackground != nil
    }

    private static func enroll() async throws {
        guard let profile = UserManager.shared.profile, store.accountKey != nil else {
            throw EnrollError.noAccount
        }
        guard let manifest = ResearchConfig.shared.available,
              ResearchConfig.shared.isOpen() else { throw EnrollError.notOpen }
        guard let outcome = store.state.pendingBackground,
              let consentAt = store.state.consentAt,
              let language = store.state.consentLanguage else { throw EnrollError.notReady }
        let account = store.accountKey

        // 账号可能只建在了本机（注册时离线）。纳入要求服务端有这个账号，先补上。
        _ = try? await APIClient.shared.registerUser(profile)

        let resp: APIClient.EnrollResearchResponse
        do {
            resp = try await APIClient.shared.enrollResearch(
                internalUserID: profile.deviceID,
                manifestID: manifest.manifestID,
                consentVersion: store.state.consentVersion ?? ResearchConsent.textVersion,
                consentLanguage: language,
                consentOccurredAt: consentAt,
                eligibilityVersion: ResearchEligibility.version,
                // 本工程未实现旧库查询：如实报 unknown，不写成 new
                priorUse: .unknown,
                isTest: AppEnvironment.isTestAccount || manifest.isTest)
        } catch let error as ResearchAPIError {
            if error.isRetryable { throw EnrollError.network }
            throw EnrollError.refused(error.reasonCode ?? "refused")
        } catch {
            throw EnrollError.network
        }
        // 等待期间换了账号：这个研究编号不属于现在登录的人，丢弃
        guard store.accountKey == account else { throw EnrollError.noAccount }

        let now = Date()
        store.update { s in
            s.participation = .enrolled
            s.participantID = resp.participantID
            s.manifestID = manifest.manifestID
            s.studyID = resp.studyID
            s.windowStart = manifest.collectionStartAt
            s.windowEnd = manifest.collectionEndAt
            s.postTriggerCount = manifest.postTriggerCount
            // 背景表进入可靠上传队列，带着**作答时**的时间与语言
            s.surveys[SurveyCenter.backgroundKey] = SurveyRecord(
                instanceID: UUID(),
                formKey: outcome.formKey,
                formVersion: outcome.formVersion,
                translationVersion: outcome.translationVersion,
                language: outcome.language,
                invitedAt: outcome.startedAt ?? outcome.submittedAt ?? now,
                qualifyingAttemptsAtInvite: 0,
                status: SurveyCenter.status(for: outcome.answers),
                startedAt: outcome.startedAt,
                submittedAt: outcome.submittedAt ?? now,
                timingClass: "background",
                answers: outcome.answers)
            s.pendingBackground = nil
        }
        // 首次练习前问卷：纳入成功即邀请（一次）。此前是否已经练过，
        // 由提交时的时间定位如实反映（late_pre），不在这里判断。
        SurveyCenter.invite(SurveyCenter.preKey, now: now)
        ResearchUploader.shared.scheduleFlush()
    }

    /// 退出研究。**立即**在端侧停止采集并清空全部待传研究内容，不等服务端。
    ///
    /// 只留下一条最小的退出指令：联网后先同步它，之后不再上传任何东西。
    /// 离线退出的人，其旧队列绝不会在恢复联网时被传上去。
    ///
    /// 退出 ≠ 删除账号：业务学习记录照常保留。退出前已到服务端的研究资料
    /// 按知情说明处理——正式保留策略审定前，导出一律排除退出者。
    static func withdraw(now: Date = Date()) {
        let s = store.state
        let pending: ResearchState.PendingWithdrawal? = s.participantID.map {
            .init(participantID: $0,
                  consentVersion: s.consentVersion ?? ResearchConsent.textVersion,
                  language: LocalizationManager.shared.language,
                  occurredAt: now)
        }
        stopLocally(as: .withdrawn)
        store.update { $0.pendingWithdrawal = pending }
        ResearchUploader.shared.scheduleFlush()
    }

    /// 端侧停止采集并清空研究内容。`withdraw` 与「服务端已停收」两条路径共用。
    static func stopLocally(as participation: ResearchState.Participation) {
        ResearchEventLog.shared.clearPendingOnWithdrawal()
        ResearchAttemptLog.shared.clearPendingOnWithdrawal()
        AdviceRequestLog.shared.clearPendingOnWithdrawal()
        // 只停**研究采集**：业务积分不清零（本轮积分功能本就关闭）
        RewardEventLog.shared.clearPendingOnWithdrawal()
        SurveyCenter.reset()
        store.update { s in
            s.participation = participation
            s.participantID = nil
            s.manifestID = nil
            s.studyID = nil
            s.windowStart = nil
            s.windowEnd = nil
            s.pendingBackground = nil
            s.backgroundDraft = nil
            s.backgroundStartedAt = nil
            s.backgroundLanguage = nil
            s.eligibility = participation == .ineligible ? "excluded:other" : nil
        }
    }
}
