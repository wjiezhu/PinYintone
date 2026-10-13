import XCTest
@testable import PinYintone

/// 参加与退出研究的状态迁移（需求 R01 / R02 / R08，验收 A02–A06、A21）。
///
/// 网络用 `StubURLProtocol` 拦截，所以这里验证的是 **App 实际发出的请求**
/// 与各种失败情形下的本机状态，而不是脚本自己拼的请求。
@MainActor
final class ResearchEnrollmentTests: XCTestCase {

    private var store: ResearchStore { .shared }
    private var savedProfile: Data?

    override func setUp() {
        super.setUp()
        savedProfile = UserDefaults.standard.data(forKey: "pt_user_profile")
        // 建立一个本机学生账号（纳入要求先有账号）
        let profile = ResearchTestSupport.profile(appleID: "apple-\(UUID().uuidString)")
        UserDefaults.standard.set(try? JSONEncoder().encode(profile), forKey: "pt_user_profile")
        UserManager.shared.bootstrap()
        ResearchConfig.shared.setAvailableForTesting(ResearchTestSupport.manifest())
        StubURLProtocol.install()
        StubURLProtocol.on("POST", "student/register") { .json(200, [:]) }
    }

    override func tearDown() {
        ResearchTestSupport.tearDown()
        if let savedProfile {
            UserDefaults.standard.set(savedProfile, forKey: "pt_user_profile")
        } else {
            UserDefaults.standard.removeObject(forKey: "pt_user_profile")
        }
        UserManager.shared.bootstrap()
        super.tearDown()
    }

    private func enrollReplies(participant: String = "participant-1") {
        StubURLProtocol.on("POST", "research/enroll") {
            .json(200, ["participantID": participant, "studyID": "study-test",
                        "alreadyEnrolled": false])
        }
        StubURLProtocol.on("POST", "research/surveys") {
            .json(200, ["surveyInstanceID": "x", "alreadySubmitted": false,
                        "status": "complete", "updated": true])
        }
    }

    // MARK: - 合格者被纳入（A03 / A04）

    func testEligibleAdultMoroccanHSKLearnerIsEnrolledWithUnknownPriorUse() async throws {
        enrollReplies()
        ResearchConsent.grant()
        let outcome = try await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
        XCTAssertEqual(outcome, .eligible)

        let s = store.state
        XCTAssertEqual(s.participation, .enrolled)
        XCTAssertEqual(s.participantID, "participant-1")
        XCTAssertEqual(s.manifestID, "manifest-test")
        XCTAssertNotNil(s.window)
        XCTAssertNil(s.pendingBackground, "纳入成功后暂存的答卷应已转入上传队列")
        XCTAssertTrue(ResearchGate.shouldCollect())

        let body = try XCTUnwrap(StubURLProtocol.requests(to: "research/enroll").first?.body)
        XCTAssertEqual(body["eligibilityStatus"] as? String, "eligible")
        XCTAssertEqual(body["eligibilityVersion"] as? String, ResearchEligibility.version)
        // 使用史如实报 unknown，不为通过检查写成 new
        XCTAssertEqual(body["priorUseStatus"] as? String, "unknown")
        XCTAssertEqual(body["priorUseEvidence"] as? String, "insufficient")
        XCTAssertEqual(body["internalUserID"] as? String, "device-test")
        XCTAssertEqual(body["consentVersion"] as? String, ResearchConsent.textVersion)
        XCTAssertTrue(["zh", "en", "fr", "ar"].contains(body["consentLanguage"] as? String ?? ""),
                      "同意语言必须是 App 内的界面语言")
        XCTAssertEqual(body["isTest"] as? Bool, true, "开发构建一律是测试数据")
    }

    /// 账号先于纳入：纳入之前先向服务端补建账号（注册时可能离线）
    func testAccountIsRegisteredBeforeEnrolling() async throws {
        enrollReplies()
        ResearchConsent.grant()
        try await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
        let paths = StubURLProtocol.requests.map(\.path)
        let register = try XCTUnwrap(paths.firstIndex { $0.hasSuffix("student/register") })
        let enroll = try XCTUnwrap(paths.firstIndex { $0.hasSuffix("research/enroll") })
        XCTAssertLessThan(register, enroll)
    }

    /// 没有账号：不进入纳入，也不卡死（A02）
    func testNoAccountMeansNoResearchEntry() {
        UserDefaults.standard.removeObject(forKey: "pt_user_profile")
        UserManager.shared.bootstrap()
        XCTAssertNil(store.accountKey)
        XCTAssertFalse(ResearchEnrollment.canJoinNow())
        ResearchConsent.grant()                       // 没有账号：写不进去
        XCTAssertEqual(store.state.participation, .notAsked)
    }

    /// 背景表带着**作答时**的时间与语言进入上传队列；随后邀请首次练习前问卷
    func testBackgroundIsQueuedWithOriginalTimestampsAndPreSurveyInvited() async throws {
        enrollReplies()
        ResearchConsent.grant()
        let started = Date().addingTimeInterval(-900), submitted = Date().addingTimeInterval(-800)
        try await ResearchEnrollment.submitBackground(
            ResearchTestSupport.background(startedAt: started, submittedAt: submitted))

        let bg = try XCTUnwrap(store.state.surveys[SurveyCenter.backgroundKey])
        XCTAssertEqual(bg.status, .complete)
        XCTAssertEqual(bg.timingClass, "background")
        XCTAssertEqual(bg.invitedAt.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(bg.submittedAt?.timeIntervalSince1970 ?? 0,
                       submitted.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(bg.answers.count, 3)

        let pre = try XCTUnwrap(store.state.surveys[SurveyCenter.preKey])
        XCTAssertEqual(pre.status, .invited)
        XCTAssertEqual(pre.qualifyingAttemptsAtInvite, 0)
    }

    // MARK: - 不合格与无法判定（A05）

    func testIneligibleOrUndeterminedLearnersAreNotEnrolledAndNothingIsUploaded() async throws {
        let cases: [(SurveyOutcome, ResearchEligibility.Outcome)] = [
            (ResearchTestSupport.background(adult: "minor"), .excluded(.age)),
            (ResearchTestSupport.background(nationality: ["FR"]), .excluded(.nationality)),
            (ResearchTestSupport.background(stage: "hsk4_plus"), .excluded(.courseStage)),
            (ResearchTestSupport.background(adult: nil), .pending),              // 关键题没答
            (ResearchTestSupport.background(nationality: ["prefer_not"]), .pending),
            (ResearchTestSupport.background(stage: nil), .pending),
        ]
        for (answers, expected) in cases {
            ResearchTestSupport.freshAccount()
            ResearchConsent.grant()
            let outcome = try await ResearchEnrollment.submitBackground(answers)
            XCTAssertEqual(outcome, expected)
            let s = store.state
            XCTAssertEqual(s.participation, .ineligible, "\(expected)")
            XCTAssertNil(s.participantID)
            XCTAssertNil(s.pendingBackground, "背景答案用完即清，不留在本机待传")
            XCTAssertNil(s.surveys[SurveyCenter.backgroundKey])
            XCTAssertFalse(ResearchGate.shouldCollect())
        }
        XCTAssertTrue(StubURLProtocol.requests(to: "research/enroll").isEmpty,
                      "不合格者不得调用纳入接口")
        XCTAssertTrue(StubURLProtocol.requests(to: "research/surveys").isEmpty,
                      "不合格者的背景答案不得上传")
    }

    /// 明确拒绝：不创建参与者、不发任何研究请求
    func testDecliningCreatesNoParticipant() {
        ResearchConsent.decline()
        XCTAssertEqual(store.state.participation, .declined)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - 纳入失败（A06）

    /// 断网：不回滚同意、不丢答卷，状态停在「已同意待纳入」，可重试
    func testNetworkFailureKeepsConsentAndAnswersForRetry() async {
        ResearchConsent.grant()
        let consentAt = store.state.consentAt
        do {
            try await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
            XCTFail("断网时应抛错")
        } catch let error as ResearchEnrollment.EnrollError {
            XCTAssertEqual(error, .network)
        } catch { XCTFail("\(error)") }

        let s = store.state
        XCTAssertEqual(s.participation, .consentedPending, "本地同意不等于已参加")
        XCTAssertEqual(s.eligibilityOutcome, .eligible)
        XCTAssertNotNil(s.pendingBackground, "答卷必须保存下来")
        XCTAssertEqual(s.consentAt, consentAt, "同意时间不因失败而改变")
        XCTAssertNil(s.participantID)
        XCTAssertTrue(ResearchEnrollment.isAwaitingEnrollment)
        XCTAssertFalse(ResearchGate.shouldCollect(), "服务端确认纳入之前不产生研究日志")
    }

    /// 重试成功：用的是原来的同意时间与原来的答卷
    func testRetryAfterFailureEnrollsWithOriginalConsentTimeAndAnswers() async throws {
        ResearchConsent.grant(now: Date().addingTimeInterval(-300))
        let answered = ResearchTestSupport.background(submittedAt: Date().addingTimeInterval(-250))
        _ = try? await ResearchEnrollment.submitBackground(answered)
        XCTAssertEqual(store.state.participation, .consentedPending)

        enrollReplies(participant: "participant-retry")
        try await ResearchEnrollment.retryEnrollment()

        XCTAssertEqual(store.state.participantID, "participant-retry")
        let bodies = StubURLProtocol.requests(to: "research/enroll").map(\.body)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(bodies[0]["consentOccurredAt"] as? String,
                       bodies[1]["consentOccurredAt"] as? String,
                       "重试不得用新的同意时间")
        XCTAssertEqual(store.state.surveys[SurveyCenter.backgroundKey]?.submittedAt?
                        .timeIntervalSince1970 ?? 0,
                       answered.submittedAt!.timeIntervalSince1970, accuracy: 0.01)
    }

    /// 服务端明确拒绝（如已退出过）：重试无用，如实报告，不无限转圈
    func testServerRefusalIsReportedAsNotRetryable() async {
        StubURLProtocol.on("POST", "research/enroll") {
            .json(409, ["detail": "withdrawn：已退出本研究，本轮不再重新纳入"])
        }
        ResearchConsent.grant()
        do {
            try await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
            XCTFail("应抛错")
        } catch let error as ResearchEnrollment.EnrollError {
            XCTAssertEqual(error, .refused("withdrawn"))
        } catch { XCTFail("\(error)") }
        XCTAssertNil(store.state.participantID)
    }

    /// 配置已关闭：不纳入
    func testCannotEnrollWhenStudyIsNotOpen() async {
        ResearchConsent.grant()
        ResearchConfig.shared.setAvailableForTesting(nil)
        do {
            try await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
            XCTFail("应抛错")
        } catch let error as ResearchEnrollment.EnrollError {
            XCTAssertEqual(error, .notOpen)
        } catch { XCTFail("\(error)") }
        XCTAssertTrue(StubURLProtocol.requests(to: "research/enroll").isEmpty)
    }

    /// 等待纳入结果期间换了账号：这个研究编号不属于现在登录的人，丢弃
    func testEnrollmentResultIsDiscardedIfAccountChangedMeanwhile() async {
        StubURLProtocol.on("POST", "research/enroll") {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    ResearchStore.shared.activate(accountKey: "someone-else-\(UUID())")
                }
            }
            return .json(200, ["participantID": "participant-A", "studyID": "s",
                               "alreadyEnrolled": false])
        }
        ResearchConsent.grant()
        _ = try? await ResearchEnrollment.submitBackground(ResearchTestSupport.background())
        XCTAssertNil(store.state.participantID, "A 的研究编号被记到了 B 名下")
        XCTAssertEqual(store.state.participation, .notAsked)
    }

    // MARK: - 退出（A21）

    func testWithdrawStopsCollectionAndClearsEverythingImmediatelyEvenOffline() {
        ResearchTestSupport.enrolledAccount()
        XCTAssertTrue(ResearchEventLog.shared.log(.historyOpened))
        let id = UUID()
        ResearchAttemptLog.shared.begin(attemptID: id, taskType: .fixedWord,
                                        lexemeVersionID: "lv", priorPracticeCount: nil)
        ResearchAttemptLog.shared.markCancelled(id)
        SurveyCenter.invite(SurveyCenter.preKey)
        SurveyCenter.saveDraft(SurveyCenter.preKey, SurveyDraft(index: 3))

        ResearchEnrollment.withdraw()            // 此时断网（没有登记任何回答）

        let s = store.state
        XCTAssertEqual(s.participation, .withdrawn)
        XCTAssertFalse(ResearchGate.shouldCollect())
        XCTAssertTrue(ResearchEventLog.shared.pending.isEmpty)
        XCTAssertTrue(ResearchAttemptLog.shared.pending.isEmpty)
        XCTAssertTrue(s.surveys.isEmpty, "问卷草稿与待传答案一并清除")
        XCTAssertNil(s.participantID)
        // 只留一条最小的退出指令，等联网后先同步
        XCTAssertEqual(s.pendingWithdrawal?.participantID, "participant-test")
        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened), "退出后不再采集")
    }

    func testWithdrawnParticipantIsNotInvitedAgain() {
        ResearchTestSupport.enrolledAccount()
        ResearchEnrollment.withdraw()
        XCTAssertFalse(ResearchEnrollment.canJoinNow())
    }
}
