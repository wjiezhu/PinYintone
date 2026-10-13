import XCTest

/// 研究流程的端到端界面测试（需求 §7 验收用例）。
///
/// 这些用例操作的是**真实 App 界面**，数据落到本地测试后端的数据库里；
/// 跑完之后由对账脚本按账号核对「库里有什么」与「导出里有什么」。
/// 录音用合成信号（模拟器没有真实麦克风），所以它们**不能**替代真机的音频验收。
///
/// 每个用例一个全新的测试账号（`uitest-<批次>-<用例名>`）。开发构建下纳入的
/// 参与者一律 is_test=true，正式导出默认排除。
///
/// 没给 `PT_API_BASE_URL` 时整组**跳过并说明原因**，不会假装通过。
@MainActor
final class ResearchFlowUITests: PinYintoneUITestCase {

    private var backend = ""

    override func setUp() async throws {
        try await super.setUp()
        backend = try requireBackend()
    }

    // MARK: - 步骤

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 首页的「参加研究」入口出现，说明研究配置已取到并且与本构建匹配
    private func openResearchFromHome(file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["home.research"], timeout: 25, file: file, line: line)
    }

    /// 知情同意 → 背景表（成年、摩洛哥、给定课程）→ 等服务端确认纳入
    private func enroll(stage: String = "hsk2", file: StaticString = #filePath, line: UInt = #line) {
        openResearchFromHome(file: file, line: line)
        agreeToConsent(file: file, line: line)
        answerBackground(stage: stage)
        XCTAssertTrue(element("research.enrolledTitle").waitForExistence(timeout: 25),
                      "背景表提交后应得到服务端的纳入确认", file: file, line: line)
    }

    private func answerPreSurvey(from question: Int = 1) {
        if question <= 1 { choose("sometimes"); surveyNext() }          // PRE01
        if question <= 2 { choose("distinguish"); surveyNext() }        // PRE02
        if question <= 3 { choose("mostly_can"); surveyNext() }         // PRE03
        if question <= 4 { choose("days3_5"); surveyNext() }            // PRE04
        if question <= 5 { choose("replay"); surveyNext() }             // PRE05
        choose("hear_model"); surveySubmit()                            // PRE06
    }

    private func answerPostSurvey() {
        choose("agree"); surveyNext()             // POST01
        choose("agree"); surveyNext()             // POST02
        choose("neutral"); surveyNext()           // POST03
        choose("none"); surveyNext()              // POST04
        // POST05 是开放题：键盘弹出时提交键仍然点得到
        let text = app.textViews["survey.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap()
        text.typeText("ok")
        XCTAssertTrue(app.buttons["survey.submit"].isHittable, "键盘弹出后提交键不应被挡住")
        surveySubmit()
    }

    private func openPractice() {
        tap(app.buttons["home.tone"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10))
    }

    private func backToHome() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["home.tone"].waitForExistence(timeout: 10))
    }

    private func openSettings() {
        tab(2)
        XCTAssertTrue(element("debug.participation").waitForExistence(timeout: 10))
    }

    private func closeSurveyResult(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element("survey.result").waitForExistence(timeout: 15),
                      "提交后应看到问卷的真实状态", file: file, line: line)
        tap(app.buttons["survey.close"], file: file, line: line)
    }

    // MARK: - A02 A03 A08 A12 A14：主路径

    /// 语言 → 登录 → 首页 → 自愿参加 → 知情 → 背景表 → 纳入 → 练习前问卷 →
    /// 五次练习 → 结束反馈后才邀请使用后问卷 → 稍后填写 → 从首页恢复 → 提交。
    func testFullFlowFromSignInToPostSurvey() {
        launch(reset: true, baseURL: backend, login: newLoginID("full"))
        signIn(chooseLanguage: "zh")                      // A02：先有账号
        XCTAssertTrue(app.buttons["home.tone"].exists, "登录后直接可以练习，没有强制前测")

        openResearchFromHome()
        XCTAssertTrue(app.buttons["consent.decline"].waitForExistence(timeout: 10),
                      "「暂不参加」与「同意」同时可见")
        shot("flow-01-consent")
        agreeToConsent()
        XCTAssertTrue(app.buttons["survey.option.adult"].waitForExistence(timeout: 10))
        shot("flow-02-background-question")
        answerBackground(stage: "hsk2")
        XCTAssertTrue(element("research.enrolledTitle").waitForExistence(timeout: 25),
                      "A03：成年、摩洛哥、HSK2 应通过并得到研究编号")
        shot("flow-03-enrolled-pre-invite")

        tap(app.buttons["surveyInvite.start"])
        XCTAssertTrue(app.buttons["survey.option.sometimes"].waitForExistence(timeout: 10))
        shot("flow-04-pre-survey-question")
        answerPreSurvey()
        XCTAssertTrue(element("survey.result").waitForExistence(timeout: 15))
        shot("flow-05-pre-survey-submitted")
        tap(app.buttons["survey.close"])

        // 五次固定词练习：同一个词重录也计次
        openPractice()
        for round in 1...5 {
            recordAndWaitForResult()
            XCTAssertFalse(app.buttons["surveyInvite.start"].exists,
                           "第 \(round) 次：结果还在看的时候不邀请问卷")
            if round == 2 {
                // 回听与示范各点一次，产生真实的播放事件
                tap(app.buttons["practice.replay"])
                Thread.sleep(forTimeInterval: 1.2)
            }
            if round < 5 { tap(app.buttons["practice.tryAgain"]) }
        }
        shot("flow-06-fifth-result")
        // 结束这次反馈（换下一个词）——这时才出现使用后问卷的邀请
        tap(app.buttons["practice.next"])
        XCTAssertTrue(app.buttons["surveyInvite.start"].waitForExistence(timeout: 10),
                      "A08：第五次有效结果看完后邀请一次使用后问卷")
        shot("flow-07-post-invite")

        // A12：稍后填写，再从首页入口恢复——不需要再练五次
        tap(app.buttons["surveyInvite.later"])
        backToHome()
        let resume = app.buttons["home.survey.usability_short_v1"]
        XCTAssertTrue(resume.waitForExistence(timeout: 10), "稍后填写的问卷应在首页留有入口")
        shot("flow-08-home-survey-notice")
        resume.tap()
        XCTAssertTrue(app.buttons["survey.option.agree"].waitForExistence(timeout: 10))
        shot("flow-09-post-survey-question")
        answerPostSurvey()
        XCTAssertTrue(element("survey.result").waitForExistence(timeout: 15))
        shot("flow-10-post-survey-submitted")
        tap(app.buttons["survey.close"])

        openSettings()
        XCTAssertEqual(debugValue("participation"), "enrolled")
        XCTAssertEqual(debugValue("qualifying"), "5", "五次有效结果，计五次")
        waitForDebug("backgroundAcked", toEqual: "yes")
        waitForDebug("pendingSurveys", toEqual: "0")
        waitForDebug("pendingAttempts", toEqual: "0")
        waitForDebug("pendingEvents", toEqual: "0")
        XCTAssertEqual(debugValue("rejectedByServer"), "0", "服务端不应拒收任何一条")
        shot("flow-11-settings-research")
    }

    // MARK: - A10 A11 A13：草稿恢复与断网补传

    /// 问卷答到一半杀掉 App；断网状态下恢复草稿、答完提交 → 如实显示「已保存，等待联网」；
    /// 恢复联网后补传，恰有一份。
    func testSurveyDraftSurvivesRestartAndOfflineSubmitIsUploadedLater() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("offline"))
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.start"])
        choose("often"); surveyNext()                 // PRE01
        choose("imitate_character"); surveyNext()     // PRE02
        XCTAssertTrue(app.buttons["survey.option.mostly_can"].waitForExistence(timeout: 5))
        app.terminate()                               // A10：答到第三题时被杀掉

        launch(reset: false, baseURL: Self.offlineURL)    // 断网重开
        let resume = app.buttons["home.survey.tone_needs_v1"]
        XCTAssertTrue(resume.waitForExistence(timeout: 15), "重启后首页应有继续填写的入口")
        resume.tap()
        XCTAssertTrue(element("survey.progress.3").waitForExistence(timeout: 10),
                      "A10：应回到上次答到的第三题，前面的答案还在")
        shot("offline-01-draft-resumed")
        answerPreSurvey(from: 3)
        XCTAssertTrue(element("survey.result").waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["survey.retryUpload"].waitForExistence(timeout: 10),
                      "A11：断网时不能显示成「已提交」，应是已保存并可重试")
        shot("offline-02-saved-waiting-for-network")
        tap(app.buttons["survey.close"])
        openSettings()
        XCTAssertEqual(debugValue("pendingSurveys"), "1", "答案在本机待传")
        shot("offline-03-settings-pending")

        app.terminate()
        launch(reset: false, baseURL: backend)            // 恢复联网
        openSettings()
        waitForDebug("pendingSurveys", toEqual: "0", timeout: 30)
        waitForDebug("backgroundAcked", toEqual: "yes")
        XCTAssertEqual(debugValue("rejectedByServer"), "0")
        shot("offline-04-settings-uploaded")
    }

    // MARK: - A05：拒绝、不符合

    func testDecliningKeepsEverythingUsableAndCollectsNothing() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("decline"))
        signIn()
        openResearchFromHome()
        tap(app.buttons["consent.decline"])
        XCTAssertTrue(app.buttons["home.tone"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["home.research"].exists, "明确拒绝后首页不再反复邀请")

        openPractice()
        recordAndWaitForResult()                          // 普通练习不降级
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("participation"), "declined")
        XCTAssertEqual(debugValue("collecting"), "no")
        XCTAssertEqual(debugValue("pendingAttempts"), "0", "未参加者不产生研究记录")
        XCTAssertEqual(debugValue("pendingEvents"), "0")
        XCTAssertTrue(app.buttons["settings.researchJoin"].exists, "之后仍可从设置主动参加")
        shot("decline-01-settings")
    }

    func testMinorIsNotEnrolledAndNothingIsUploaded() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("minor"))
        signIn()
        openResearchFromHome()
        agreeToConsent()
        answerBackground(adult: "minor")
        XCTAssertTrue(element("research.message.research_ineligible_title")
            .waitForExistence(timeout: 15), "未成年不纳入，给一句平实的说明")
        shot("ineligible-01-message")
        tap(app.buttons["research.done"])

        openPractice()
        recordAndWaitForResult()
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("participation"), "ineligible")
        XCTAssertEqual(debugValue("pendingAttempts"), "0")
        XCTAssertEqual(debugValue("pendingEvents"), "0")
        XCTAssertEqual(debugValue("pendingSurveys"), "0", "筛选未通过者的背景答案不上传")
    }

    func testMissingCourseStageIsNotAssumedEligible() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("nostage"))
        signIn()
        openResearchFromHome()
        agreeToConsent()
        answerBackground(stage: nil)                      // 课程阶段一题跳过
        XCTAssertTrue(element("research.message.research_ineligible_title")
            .waitForExistence(timeout: 15), "关键题没答不推定符合")
        tap(app.buttons["research.done"])
        openSettings()
        XCTAssertEqual(debugValue("participation"), "ineligible")
        XCTAssertEqual(debugValue("pendingSurveys"), "0")
    }

    // MARK: - A06：纳入失败

    func testEnrollmentFailureOffersRetryAndDoesNotBlockPractice() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("retry"))
        signIn()
        XCTAssertTrue(app.buttons["home.research"].waitForExistence(timeout: 25))
        app.terminate()

        launch(reset: false, baseURL: Self.offlineURL)    // 断网
        openResearchFromHome()
        agreeToConsent()
        answerBackground()
        XCTAssertTrue(app.buttons["research.retryEnroll"].waitForExistence(timeout: 40),
                      "A06：纳入失败应给出重试，不能一直转圈")
        XCTAssertTrue(app.buttons["research.later"].exists, "也可以先去练习")
        shot("retry-01-enroll-failed")
        tap(app.buttons["research.later"])

        openPractice()
        recordAndWaitForResult()                          // 研究没走完不影响练习
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("participation"), "consentedPending")
        XCTAssertEqual(debugValue("pendingAttempts"), "0", "确认纳入前不产生研究日志")

        app.terminate()
        launch(reset: false, baseURL: backend)            // 恢复联网，从设置回来接着做
        openSettings()
        tap(app.buttons["settings.researchJoin"])
        XCTAssertTrue(element("research.enrolledTitle").waitForExistence(timeout: 30),
                      "重试后纳入成功")
        tap(app.buttons["surveyInvite.decline"])          // 明确不填练习前问卷
        openSettings()
        XCTAssertEqual(debugValue("participation"), "enrolled")
        waitForDebug("backgroundAcked", toEqual: "yes")
        waitForDebug("pendingSurveys", toEqual: "0")
    }

    // MARK: - A17 A09：自测

    func testSelfTestShowsNoEvaluationAndCanBeCancelledOrFinished() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("selftest"))
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.later"])

        openPractice()
        tap(app.buttons["practice.more"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS '自测'")).firstMatch)
        XCTAssertTrue(element("selfTest.progress").waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["practice.listen"].exists, "自测没有示范")
        XCTAssertFalse(app.buttons["practice.next"].exists)
        XCTAssertFalse(element("practice.chart").exists, "自测不显示曲线")
        XCTAssertFalse(app.buttons["practice.mode.curve"].exists)
        recordOnce()
        Thread.sleep(forTimeInterval: 2.0)
        XCTAssertFalse(element("practice.result").exists, "自测不显示本次结果")
        shot("selftest-01-in-progress")
        tap(app.buttons["selfTest.exit"])                 // 随时取消
        XCTAssertTrue(app.buttons["practice.listen"].waitForExistence(timeout: 10),
                      "取消后回到普通练习")

        // 再来一次并做完
        tap(app.buttons["practice.more"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS '自测'")).firstMatch)
        XCTAssertTrue(element("selfTest.progress").waitForExistence(timeout: 10))
        for _ in 0..<8 where !element("selfTest.finished").exists {
            recordOnce()
            Thread.sleep(forTimeInterval: 2.0)
        }
        XCTAssertTrue(element("selfTest.finished").waitForExistence(timeout: 10))
        XCTAssertFalse(element("practice.result").exists, "完成页不给分数或结论")
        shot("selftest-02-finished")
        tap(app.buttons["selfTest.back"])
        XCTAssertTrue(app.buttons["practice.listen"].waitForExistence(timeout: 10),
                      "完成后回到普通练习，没有被锁住")
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("qualifying"), "0", "A09：自测不计入使用后问卷的次数")
        waitForDebug("pendingAttempts", toEqual: "0")
    }

    // MARK: - A14 A09：技术失败

    func testTechnicalFailureIsRecordedWithoutAScoreAndDoesNotCount() {
        launch(reset: true, baseURL: backend, language: "zh", audio: "silent",
               login: newLoginID("silent"))
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.later"])
        openPractice()
        recordOnce()
        XCTAssertTrue(element("practice.failure").waitForExistence(timeout: 10))
        XCTAssertFalse(element("practice.result").exists, "技术失败不显示成绩")
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("qualifying"), "0", "技术失败不计次")
        waitForDebug("pendingAttempts", toEqual: "0")

        app.terminate()
        launch(reset: false, baseURL: backend, audio: "match")
        openPractice()
        recordAndWaitForResult()
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("qualifying"), "1")
        waitForDebug("pendingAttempts", toEqual: "0")
        XCTAssertEqual(debugValue("rejectedByServer"), "0")
    }

    // MARK: - A21：退出研究

    func testWithdrawingOfflineStopsCollectionAndIsConfirmedWhenBackOnline() {
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("withdraw"))
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.later"])
        openPractice()
        recordAndWaitForResult()
        tap(app.buttons["practice.tryAgain"])
        recordAndWaitForResult()
        backToHome()
        openSettings()
        waitForDebug("pendingAttempts", toEqual: "0")     // 两次都已送达
        app.terminate()

        launch(reset: false, baseURL: Self.offlineURL)    // 断网后再练一次，然后退出
        openPractice()
        recordAndWaitForResult()
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("pendingAttempts"), "1")
        tap(app.buttons["settings.researchWithdraw"])
        let confirm = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "退出研究",
                        "settings.researchWithdraw")).firstMatch
        tap(confirm)
        XCTAssertEqual(debugValue("participation"), "withdrawn")
        XCTAssertEqual(debugValue("pendingAttempts"), "0", "A21：退出立刻清空待传研究内容")
        XCTAssertEqual(debugValue("pendingEvents"), "0")
        XCTAssertEqual(debugValue("pendingWithdrawal"), "yes", "只留一条待确认的退出指令")
        XCTAssertEqual(debugValue("collecting"), "no")
        shot("withdraw-01-offline")

        openPracticeFromTab()
        recordAndWaitForResult()                          // 退出后照常练习
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("pendingAttempts"), "0", "退出后不再产生研究记录")

        app.terminate()
        launch(reset: false, baseURL: backend)
        openSettings()
        waitForDebug("pendingWithdrawal", toEqual: "no", timeout: 30)
        XCTAssertEqual(debugValue("participation"), "withdrawn")
        shot("withdraw-02-confirmed")
    }

    private func openPracticeFromTab() {
        tab(0)
        openPractice()
    }

    // MARK: - A20：账号隔离与跨设备

    func testAccountsDoNotShareResearchStateAndSameAccountIsOneParticipant() {
        let first = newLoginID("acct-a")
        let second = newLoginID("acct-b")
        launch(reset: true, baseURL: backend, language: "zh", login: first)
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.later"])
        openPractice()
        recordAndWaitForResult()
        tap(app.buttons["practice.tryAgain"])
        recordAndWaitForResult()
        backToHome()
        openSettings()
        XCTAssertEqual(debugValue("qualifying"), "2")
        waitForDebug("pendingAttempts", toEqual: "0")
        app.terminate()

        // 换一个账号登录：看不到上一个人的身份、计数和问卷
        launch(reset: false, baseURL: backend, login: second)
        openSettings()
        tap(app.buttons["settings.switchAccount"])
        tap(app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "切换账号",
                        "settings.switchAccount")).firstMatch)
        signIn()
        openSettings()
        XCTAssertEqual(debugValue("participation"), "notAsked", "A20：新账号没有研究身份")
        XCTAssertEqual(debugValue("qualifying"), "0")
        XCTAssertEqual(debugValue("pendingSurveys"), "0")
        tab(0)
        XCTAssertFalse(app.buttons["home.survey.tone_needs_v1"].exists,
                       "上一个账号的待填问卷不出现在这个账号下")
        app.terminate()

        // 换回第一个账号：身份与计数还在
        launch(reset: false, baseURL: backend, login: first)
        openSettings()
        tap(app.buttons["settings.switchAccount"])
        tap(app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "切换账号",
                        "settings.switchAccount")).firstMatch)
        signIn()
        openSettings()
        XCTAssertEqual(debugValue("participation"), "enrolled")
        XCTAssertEqual(debugValue("qualifying"), "2")
        app.terminate()

        // 同一账号换一台设备（清空本机后重新登录、重新走参加流程）：仍是同一位参与者
        launch(reset: true, baseURL: backend, language: "zh", login: first)
        signIn()
        enroll()
        tap(app.buttons["surveyInvite.later"])
        openSettings()
        XCTAssertEqual(debugValue("participation"), "enrolled")
    }
}
