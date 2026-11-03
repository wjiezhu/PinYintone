import XCTest

/// 每个模块至少真实走完一遍主流程，不只是把页面打开（录音是合成信号）。
/// 声调练习、自测、研究流程、现场实测已有各自的用例，这里补送气、自由文本、教师端、
/// 以及西语 / 意语界面。需要本地测试后端的用例见 `requireBackend`。
@MainActor
final class ModuleSmokeUITests: PinYintoneUITestCase {

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func labelContains(_ text: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS %@", text)
    }

    /// 送气：进页面不自动开麦 → 点开始 → 点停止 → 出结果 → 换词再来一次
    func testAspirationRecordsToAResultAndMovesOn() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh", audio: "delayed",
               login: newLoginID("aspiration"))
        signIn()
        tap(app.buttons["home.aspiration"])
        XCTAssertTrue(element("aspiration.target").waitForExistence(timeout: 10), "词条要标明送气与否")
        XCTAssertFalse(element("aspiration.result").exists, "没录音不该有结果")

        for round in 1...2 {
            let record = app.buttons["practice.record"]
            XCTAssertTrue(record.waitForExistence(timeout: 10))
            record.tap()
            Thread.sleep(forTimeInterval: 1.8)
            record.tap()
            XCTAssertTrue(element("aspiration.result").waitForExistence(timeout: 10),
                          "第 \(round) 次停止后应出现结果")
            shot("module-aspiration-result-\(round)")
            tap(app.buttons["aspiration.next"])
            XCTAssertTrue(element("aspiration.target").waitForExistence(timeout: 10))
        }
    }

    /// 自由文本：输入 → 分词 → 开始练习 → 录音 → 出分 → 换下一个词
    func testFreeTextFromInputToScore() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh", login: newLoginID("freetext"))
        signIn()
        tap(app.buttons["home.freeText"])
        let input = app.textViews.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("我们现在喝水")
        shot("module-freetext-input")
        tap(app.buttons["freeText.tokenize"])

        tap(app.buttons["开始练习"])
        shot("module-freetext-practice")
        recordOnce()
        let score = app.descendants(matching: .any).matching(labelContains("本次结果")).firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 15), "录音后应出现本次结果")
        shot("module-freetext-result")

        tap(app.buttons["freeText.next"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10))
    }

    /// 教师端：注册 → 服务端发 6 位班级码 → 进入数据面板
    func testTeacherRegistersAndReachesDashboard() throws {
        let backend = try requireBackend()
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("teacher"))
        tap(app.buttons["role.teacher"])

        let name = app.textFields["姓名"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "教师注册页没有出现")
        name.tap()
        name.typeText("Test Teacher")
        let email = app.textFields["电子邮箱"]
        email.tap()
        email.typeText("\(UUID().uuidString)@example.test")
        let password = app.secureTextFields["密码"]
        password.tap()
        password.typeText(UUID().uuidString)
        shot("module-teacher-signup")
        tap(app.buttons["继续"])

        let enter = app.buttons["进入数据面板"]
        XCTAssertTrue(enter.waitForExistence(timeout: 20), "注册后应显示班级码")
        let code = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9]{6}")).firstMatch
        XCTAssertTrue(code.exists, "班级码应是 6 位数字")
        shot("module-teacher-classcode")
        tap(enter)

        tap(app.tabBars.buttons["教师"], timeout: 15)
        Thread.sleep(forTimeInterval: 1.5)
        shot("module-teacher-dashboard")
        XCTAssertFalse(app.alerts.firstMatch.exists, "数据面板不应弹错误")
    }

    /// 西语、意语：登录 → 练一次 → 历史 → 设置，用真实语言选择页进入
    func testSpanishAndItalianCoreFlow() {
        for language in ["es", "it"] {
            launch(reset: true, baseURL: Self.offlineURL, login: newLoginID("lang-\(language)"))
            signIn(chooseLanguage: language)
            shot("module-\(language)-home")
            tap(app.buttons["home.tone"])
            recordAndWaitForResult()
            shot("module-\(language)-result")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tab(1)
            Thread.sleep(forTimeInterval: 0.6)
            shot("module-\(language)-history")
            tab(2)
            Thread.sleep(forTimeInterval: 0.6)
            shot("module-\(language)-settings")
            app.terminate()
        }
    }
}
