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

    /// 邮箱验证码登录：发码 → 输错一次（提示剩余次数）→ 输对 → 进首页 → 设置里看得到邮箱。
    /// 本地后端用 console 发信器，验证码写在它的日志里（`PT_EMAIL_LOG` 指向该日志文件）。
    func testEmailCodeSignIn() throws {
        let backend = try requireBackend()
        let logPath = try XCTUnwrap(ProcessInfo.processInfo.environment["PT_EMAIL_LOG"],
                                    "未提供 PT_EMAIL_LOG：本用例要从本地后端日志里读验证码")
        let email = "uitest-\(Self.runID)-email@example.test"
        launch(reset: true, baseURL: backend, language: "zh", login: newLoginID("email"))
        tap(app.buttons["role.student"])
        tap(app.buttons["signup.emailLogin"])

        let field = app.textFields["emailLogin.email"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "邮箱登录页没有出现")
        field.tap()
        field.typeText(email)
        shot("module-email-enter")
        tap(app.buttons["emailLogin.send"])
        XCTAssertTrue(app.descendants(matching: .any)["emailLogin.sent"].waitForExistence(timeout: 20),
                      "发码后应提示验证码已发出")

        let code = try XCTUnwrap(latestCode(for: email, in: logPath), "后端日志里没找到验证码")
        let wrong = code == "000000" ? "111111" : "000000"
        let codeField = app.textFields["emailLogin.code"]
        codeField.tap()
        codeField.typeText(wrong)
        tap(app.buttons["emailLogin.submit"])
        let error = app.descendants(matching: .any)["emailLogin.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15), "输错应提示")
        XCTAssertTrue(error.label.contains("4"), "应告诉学习者还能试几次：\(error.label)")
        shot("module-email-wrong-code")

        codeField.tap()
        codeField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        codeField.typeText(code)
        tap(app.buttons["emailLogin.submit"])
        XCTAssertTrue(app.buttons["home.continueTone"].waitForExistence(timeout: 20),
                      "验证码正确应直接进入练习首页")
        if app.buttons["consent.decline"].waitForExistence(timeout: 4) {
            tap(app.buttons["research.close"])
        }
        tab(2)
        XCTAssertTrue(app.staticTexts[email].waitForExistence(timeout: 10), "设置里应显示登录邮箱")
        shot("module-email-settings")
    }

    /// 本地后端日志里发给这个邮箱的最后一个验证码
    private func latestCode(for email: String, in path: String) -> String? {
        for _ in 0..<20 {
            if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                let lines = text.split(separator: "\n").filter { $0.contains(email) && $0.contains("验证码") }
                if let line = lines.last,
                   let range = line.range(of: #"验证码 (\d{6})"#, options: .regularExpression) {
                    return String(line[range].suffix(6))
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return nil
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
