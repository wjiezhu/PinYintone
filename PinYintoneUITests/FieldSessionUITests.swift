import XCTest

/// 现场实测的端到端界面测试（2026-10-28）：参加研究（国籍选「不愿回答」也能纳入）→
/// 首页出现实测入口 → 说明页 → 前测（不显示结果）→ 训练（有反馈，练够才换词）→
/// 后测（不显示结果）→ 完成页邀请使用后问卷。
///
/// 需要本地测试后端，且其中冻结了一份**带实测协议**的测试配置
/// （`seed_manifest.py --test --field-protocol ...`）。录音是合成信号。
@MainActor
final class FieldSessionUITests: PinYintoneUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// 裸测录一次：录音 → 停止 → 等它自动进下一个词（或这一段结束）
    private func recordBareWord() {
        recordOnce()
        Thread.sleep(forTimeInterval: 1.4)
    }

    func testFieldSessionFromJoiningToFinish() throws {
        let backend = try requireBackend()
        launch(reset: true, baseURL: backend, login: newLoginID("field"))
        signIn(chooseLanguage: "zh")

        // 参加研究：国籍选「不愿回答」——本轮不限国籍，照样纳入
        tap(app.buttons["home.research"], timeout: 25)
        agreeToConsent()
        answerBackground(nationality: "prefer_not", stage: "hsk1")
        XCTAssertTrue(element("research.enrolledTitle").waitForExistence(timeout: 25),
                      "不限国籍：选「不愿回答」也应纳入")
        tap(app.buttons["surveyInvite.later"])

        // 首页的实测入口
        let entry = app.buttons["home.fieldSession"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "已参加研究、配置带实测协议：首页应有实测入口")
        shot("field-01-home-entry")
        entry.tap()

        XCTAssertTrue(element("field.intro").waitForExistence(timeout: 10))
        shot("field-02-intro")
        tap(app.buttons["field.start"])

        // 前测：不显示任何结果
        XCTAssertTrue(element("selfTest.progress").waitForExistence(timeout: 10))
        shot("field-03-pretest")
        var guardCount = 0
        while !element("field.between").exists, guardCount < 12 {
            XCTAssertFalse(app.buttons["practice.tryAgain"].exists, "前测不得显示结果")
            XCTAssertFalse(element("practice.chart").exists, "前测不得画曲线")
            recordBareWord()
            guardCount += 1
        }
        XCTAssertTrue(element("field.between").waitForExistence(timeout: 5))
        shot("field-04-pretest-done")
        tap(app.buttons["field.continue"])

        // 训练：有反馈；练够次数前「下一个」不可用
        XCTAssertTrue(element("field.trainingProgress").waitForExistence(timeout: 10))
        var shotTraining = false
        guardCount = 0
        while !element("field.between").exists, guardCount < 40 {
            recordAndWaitForResult()
            if !shotTraining { shot("field-05-training-feedback"); shotTraining = true }
            if element("field.wordDone").exists {
                if guardCount < 4 { shot("field-06-training-word-done") }
                tap(app.buttons["field.next"])
            } else {
                XCTAssertFalse(app.buttons["field.next"].isEnabled, "没练够不能换词")
                tap(app.buttons["practice.tryAgain"])
            }
            guardCount += 1
        }
        XCTAssertTrue(element("field.between").waitForExistence(timeout: 5))
        tap(app.buttons["field.continue"])

        // 后测
        XCTAssertTrue(element("selfTest.progress").waitForExistence(timeout: 10))
        shot("field-07-posttest")
        guardCount = 0
        while !element("field.finished").exists, guardCount < 12 {
            XCTAssertFalse(app.buttons["practice.tryAgain"].exists, "后测不得显示结果")
            recordBareWord()
            guardCount += 1
        }
        XCTAssertTrue(element("field.finished").waitForExistence(timeout: 5))
        // 完成页邀请使用后问卷
        XCTAssertTrue(app.buttons["surveyInvite.later"].waitForExistence(timeout: 10),
                      "做完实测邀请一次使用后问卷")
        shot("field-08-finished-survey-invite")
        tap(app.buttons["surveyInvite.later"])
        shot("field-09-finished")
        tap(app.buttons["field.back"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10),
                      "做完回到普通练习")
    }

    /// 登录后弹一次知情同意：有全文链接，不默认打勾，可以不同意；同意后才进背景表
    func testConsentPopsUpAfterSignInAndCanBeDeclined() throws {
        let backend = try requireBackend()
        launch(reset: true, baseURL: backend, login: newLoginID("popup"))
        signIn(chooseLanguage: "es", keepConsentPopup: true)
        let decline = app.buttons["consent.decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 20), "登录后应弹出研究说明")
        XCTAssertFalse(app.buttons["consent.agree"].isEnabled, "不默认打勾")
        shot("consent-01-popup-es")
        tap(app.buttons["consent.readFull"])
        XCTAssertTrue(app.buttons["consent.fullClose"].waitForExistence(timeout: 5))
        shot("consent-02-full-text-es")
        tap(app.buttons["consent.fullClose"])
        tap(decline)
        XCTAssertTrue(app.buttons["home.tone"].waitForExistence(timeout: 10), "不同意照样进首页")
        relaunch(baseURL: backend)
        XCTAssertTrue(app.buttons["home.tone"].waitForExistence(timeout: 15))
        XCTAssertFalse(decline.waitForExistence(timeout: 4), "只问一次")
    }
}
