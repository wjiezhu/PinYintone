import XCTest
@testable import PinYintone

/// 问卷的邀请、计数、草稿与提交（需求 R05，验收 A08–A13）。
@MainActor
final class SurveyCenterTests: XCTestCase {

    private var store: ResearchStore { .shared }
    private let post = SurveyCenter.postKey
    private let pre = SurveyCenter.preKey

    override func setUp() {
        super.setUp()
        StubURLProtocol.install()            // 断网：这里只看本机状态
        ResearchTestSupport.enrolledAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    @discardableResult
    private func count(_ type: ResearchAttemptRecord.TaskType = .fixedWord,
                       displayed: Bool = true, id: UUID = UUID()) -> Bool {
        SurveyCenter.recordQualifyingAttempt(id, taskType: type, resultDisplayed: displayed)
    }

    private func answer(_ q: String, _ code: String) -> SurveyAnswer {
        SurveyAnswer(questionID: q, state: .answered, optionCodes: [code],
                     textValue: nil, answeredAt: Date())
    }

    // MARK: - 合格练习计数（A08 / A09）

    /// 第 5 次合格结果呈现时达到邀请条件，且只达到一次
    func testFifthQualifyingResultMakesInvitationDueExactlyOnce() {
        for i in 1...4 { XCTAssertFalse(count(), "第 \(i) 次不应达到") }
        XCTAssertFalse(SurveyCenter.isPostInvitationDue)
        XCTAssertTrue(count(), "第 5 次应达到邀请条件")
        XCTAssertTrue(SurveyCenter.isPostInvitationDue)
        XCTAssertFalse(count(), "第 6 次不得再次触发")
        XCTAssertEqual(SurveyCenter.qualifyingCount, 6)
    }

    /// 结果没显示出来不计次；自由文本、自测不计次
    func testOnlyDisplayedFixedWordResultsCount() {
        for _ in 0..<6 { count(displayed: false) }
        for _ in 0..<6 { count(.freeText) }
        for _ in 0..<6 { count(.selfTest) }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0)
        XCTAssertFalse(SurveyCenter.isPostInvitationDue)
    }

    /// 同一次练习的结果重复呈现（重绘、旋转屏幕）不重复计次
    func testSameAttemptIsCountedOnce() {
        let id = UUID()
        for _ in 0..<5 { count(id: id) }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 1)
    }

    /// 同词重录可累计——计的是尝试，不是不同的词
    func testRepeatedRecordingsAccumulate() {
        for _ in 0..<5 { count() }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 5)
        XCTAssertTrue(SurveyCenter.isPostInvitationDue)
    }

    /// 不在采集中的练习（未参加、窗口外）不是研究数据，不计次
    func testPracticeOutsideCollectionDoesNotCount() {
        ResearchTestSupport.freshAccount()
        for _ in 0..<6 { count() }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0)

        ResearchTestSupport.enrolledAccount(windowStart: Date().addingTimeInterval(-7200),
                                            windowEnd: Date().addingTimeInterval(-3600))
        for _ in 0..<6 { count() }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0)
    }

    /// 触发次数来自纳入时记下的配置
    func testThresholdComesFromTheEnrolledManifest() {
        store.update { $0.postTriggerCount = 3 }
        XCTAssertFalse(count()); XCTAssertFalse(count())
        XCTAssertTrue(count())
    }

    // MARK: - 邀请只在结束当前反馈之后出现

    /// 达到条件只是记下「该邀请了」；用户结束当前反馈时才生成邀请
    func testInvitationIsCreatedOnlyWhenTheLearnerFinishesWithTheFeedback() throws {
        for _ in 0..<5 { count() }
        XCTAssertNil(SurveyCenter.record(post), "还在看反馈，不应已弹出邀请")

        let record = try XCTUnwrap(SurveyCenter.consumePostInvitationIfDue())
        XCTAssertEqual(record.status, .invited)
        XCTAssertEqual(record.qualifyingAttemptsAtInvite, 5)
        XCTAssertFalse(SurveyCenter.isPostInvitationDue)
        XCTAssertNil(SurveyCenter.consumePostInvitationIfDue(), "只邀请一次")
    }

    /// 达到条件后 App 被杀：重启后仍会邀请，不需要再练五次
    func testDueInvitationSurvivesRelaunch() throws {
        let key = try XCTUnwrap(store.accountKey)
        for _ in 0..<5 { count() }
        store.activate(accountKey: nil)
        store.activate(accountKey: key)
        XCTAssertTrue(SurveyCenter.isPostInvitationDue)
        XCTAssertNotNil(SurveyCenter.consumePostInvitationIfDue())
    }

    // MARK: - 邀请快照

    /// 邀请时把时间、当时的合格次数、当时的界面语言、表单与译文版本定下来
    func testInvitationSnapshotsLanguageVersionsCountAndTime() throws {
        let before = LocalizationManager.shared.language
        defer { LocalizationManager.shared.setLanguage(before) }
        LocalizationManager.shared.setLanguage("ar")
        for _ in 0..<5 { count() }
        let invitedAt = Date()
        let record = try XCTUnwrap(SurveyCenter.invite(post, now: invitedAt))
        let form = try XCTUnwrap(SurveyFormLoader.bundled[post])
        XCTAssertEqual(record.language, "ar")
        XCTAssertEqual(record.formVersion, form.formVersion)
        XCTAssertEqual(record.translationVersion, form.translationVersion)
        XCTAssertEqual(record.qualifyingAttemptsAtInvite, 5)

        // 之后改了界面语言、又练了几次：快照不漂移（A10）
        LocalizationManager.shared.setLanguage("fr")
        count(); count()
        let later = try XCTUnwrap(SurveyCenter.record(post))
        XCTAssertEqual(later.language, "ar")
        XCTAssertEqual(later.qualifyingAttemptsAtInvite, 5)
        XCTAssertEqual(later.invitedAt.timeIntervalSince1970, invitedAt.timeIntervalSince1970,
                       accuracy: 0.01)
        XCTAssertEqual(later.instanceID, record.instanceID)
    }

    func testInviteTwiceReturnsTheSameInstance() throws {
        let a = try XCTUnwrap(SurveyCenter.invite(pre))
        let b = try XCTUnwrap(SurveyCenter.invite(pre))
        XCTAssertEqual(a.instanceID, b.instanceID)
        XCTAssertEqual(a.qualifyingAttemptsAtInvite, 0, "前置问卷邀请时合格次数为 0")
    }

    /// 邀请是新的研究数据：未参加或窗口外不发出
    func testNoInvitationOutsideCollection() {
        ResearchTestSupport.freshAccount()
        XCTAssertNil(SurveyCenter.invite(pre))
        ResearchTestSupport.enrolledAccount(windowStart: Date().addingTimeInterval(-7200),
                                            windowEnd: Date().addingTimeInterval(-3600))
        XCTAssertNil(SurveyCenter.invite(post))
    }

    // MARK: - 稍后填写、草稿与恢复（A10 / A12）

    /// 「稍后填写」保留同一个实例与草稿；回来不需要重新达到次数
    func testDeferKeepsInstanceAndDraftAndCanBeResumedWithoutPracticingAgain() throws {
        for _ in 0..<5 { count() }
        let invited = try XCTUnwrap(SurveyCenter.consumePostInvitationIfDue())
        let draft = SurveyDraft(index: 2, selections: ["POST01": ["agree"]],
                                texts: [:], skipped: ["POST02"], answeredAt: [:])
        SurveyCenter.saveDraft(post, draft)
        SurveyCenter.deferSurvey(post)

        let record = try XCTUnwrap(SurveyCenter.record(post))
        XCTAssertEqual(record.status, .deferred)
        XCTAssertEqual(record.instanceID, invited.instanceID)
        XCTAssertEqual(record.draft, draft)
        XCTAssertEqual(SurveyCenter.resumable(in: store.state).map(\.formKey), [post])
        XCTAssertFalse(SurveyCenter.isPostInvitationDue, "不会再自动弹一次")
    }

    /// 草稿落盘：中途退出、切后台、重启都不丢；换账号不带出上一人的答案
    func testDraftSurvivesRelaunchAndIsNotVisibleToAnotherAccount() throws {
        let key = try XCTUnwrap(store.accountKey)
        SurveyCenter.invite(pre)
        let draft = SurveyDraft(index: 4, selections: ["PRE01": ["often"]],
                                texts: ["PRE02.other": "tons"], skipped: [], answeredAt: [:])
        SurveyCenter.saveDraft(pre, draft)

        ResearchTestSupport.enrolledAccount()                 // 另一个人登录
        XCTAssertNil(SurveyCenter.record(pre), "上一个人的问卷草稿被带了过来")

        store.activate(accountKey: key)                        // 原账号回来
        XCTAssertEqual(SurveyCenter.record(pre)?.draft, draft)
        XCTAssertNotNil(SurveyCenter.record(pre)?.startedAt)
    }

    // MARK: - 四种状态互不混淆

    func testInvitedDeferredDeclinedAndSubmittedAreDistinct() throws {
        SurveyCenter.invite(pre)
        XCTAssertEqual(SurveyDisplayStatus(try XCTUnwrap(SurveyCenter.record(pre))), .invited)
        SurveyCenter.deferSurvey(pre)
        XCTAssertEqual(SurveyDisplayStatus(try XCTUnwrap(SurveyCenter.record(pre))), .deferred)
        SurveyCenter.decline(pre)
        let declined = try XCTUnwrap(SurveyCenter.record(pre))
        XCTAssertEqual(SurveyDisplayStatus(declined), .declined)
        XCTAssertTrue(declined.answers.isEmpty, "不填写不生成任何答案")
        XCTAssertFalse(declined.isResumable)

        SurveyCenter.invite(post)
        SurveyCenter.submit(post, answers: [answer("POST01", "agree")])
        let submitted = try XCTUnwrap(SurveyCenter.record(post))
        // 只存在本机：如实显示「已保存，等待联网提交」，不是「已提交」
        XCTAssertEqual(SurveyDisplayStatus(submitted), .savedWaitingForNetwork)
        var acked = submitted
        acked.syncedStatus = acked.status
        XCTAssertEqual(SurveyDisplayStatus(acked), .submitted)
    }

    /// 最终状态之后不再变：再点稍后、再提交都不生效
    func testFinalStatusIsNotChangedAfterwards() throws {
        SurveyCenter.invite(post)
        SurveyCenter.submit(post, answers: [answer("POST01", "agree")])
        let first = try XCTUnwrap(SurveyCenter.record(post))
        SurveyCenter.deferSurvey(post)
        SurveyCenter.decline(post)
        SurveyCenter.submit(post, answers: [answer("POST01", "strongly_disagree")])
        XCTAssertEqual(SurveyCenter.record(post), first)
    }

    func testStatusFromAnswers() {
        let skipped = SurveyAnswer(questionID: "Q2", state: .skipped, optionCodes: nil,
                                   textValue: nil, answeredAt: nil)
        XCTAssertEqual(SurveyCenter.status(for: [answer("Q1", "a")]), .complete)
        XCTAssertEqual(SurveyCenter.status(for: [answer("Q1", "a"), skipped]), .partial)
        XCTAssertEqual(SurveyCenter.status(for: [skipped]), .declined)
        XCTAssertEqual(SurveyCenter.status(for: []), .declined)
    }

    // MARK: - 前置问卷的时间定位（A13）

    /// 练习前完成的是练习前调查；开始练习后才完成的是 late_pre
    func testPreSurveyTimingFollowsCompletionRelativeToFirstPractice() throws {
        SurveyCenter.invite(pre)
        SurveyCenter.submit(pre, answers: [answer("PRE01", "often")])
        XCTAssertEqual(SurveyCenter.record(pre)?.timingClass, "before_first_attempt")

        ResearchTestSupport.enrolledAccount()
        SurveyCenter.invite(pre)
        SurveyCenter.markPracticeStarted(now: Date().addingTimeInterval(-60))
        SurveyCenter.submit(pre, answers: [answer("PRE01", "often")])
        XCTAssertEqual(SurveyCenter.record(pre)?.timingClass, "late_pre")
    }

    /// 分类在**完成时**定下，之后才开始练习、才上传，都不改变它
    func testTimingClassIsFixedAtCompletionNotAtUpload() throws {
        SurveyCenter.invite(pre)
        SurveyCenter.submit(pre, answers: [answer("PRE01", "often")],
                            now: Date().addingTimeInterval(-600))
        SurveyCenter.markPracticeStarted()              // 填完之后才开始练习
        for _ in 0..<5 { count() }
        let record = try XCTUnwrap(SurveyCenter.record(pre))
        XCTAssertEqual(record.timingClass, "before_first_attempt",
                       "练习前已完成、只是晚上传的，仍是前置数据")
        XCTAssertEqual(record.qualifyingAttemptsAtInvite, 0)
    }

    /// 先练习、后参加研究的人：前置问卷如实是 late_pre
    func testLearnerWhoPractisedBeforeJoiningGetsLatePre() {
        ResearchTestSupport.freshAccount()
        SurveyCenter.markPracticeStarted(now: Date().addingTimeInterval(-3600))
        let first = store.state.firstPracticeStartedAt
        SurveyCenter.markPracticeStarted()                // 只记第一次
        XCTAssertEqual(store.state.firstPracticeStartedAt, first)
        XCTAssertEqual(SurveyCenter.timingClass(for: pre, completedAt: Date(), state: store.state),
                       "late_pre")
    }

    func testTimingClassOfOtherForms() {
        let s = ResearchState()
        XCTAssertEqual(SurveyCenter.timingClass(for: SurveyCenter.backgroundKey,
                                                completedAt: Date(), state: s), "background")
        XCTAssertEqual(SurveyCenter.timingClass(for: post, completedAt: Date(), state: s),
                       "after_practice")
    }

    // MARK: - 首页提示

    func testDismissedBannerHidesTheRowButNotTheSurvey() {
        SurveyCenter.invite(pre)
        SurveyCenter.dismissBanner()
        XCTAssertTrue(store.state.surveyBannerDismissed)
        XCTAssertEqual(SurveyCenter.resumable(in: store.state).count, 1,
                       "关掉提示不等于放弃问卷，设置里仍可进入")
        SurveyCenter.invite(post)       // 新的邀请重新显示提示
        XCTAssertFalse(store.state.surveyBannerDismissed)
    }

    func testResetClearsSurveysAndCounts() {
        for _ in 0..<5 { count() }
        SurveyCenter.invite(pre)
        SurveyCenter.reset()
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0)
        XCTAssertTrue(store.state.surveys.isEmpty)
        XCTAssertFalse(SurveyCenter.isPostInvitationDue)
    }
}
