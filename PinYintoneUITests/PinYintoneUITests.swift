import XCTest

/// 界面截图巡览：把主要页面各截一张，供人工检查版式。不需要后端
/// （后端指向一个不通的地址，研究入口因此不出现——这正是「无研究配置」时的样子）。
@MainActor
final class ScreenTourUITests: PinYintoneUITestCase {

    func testTourMainScreens() {
        launch(reset: true, baseURL: Self.offlineURL, login: newLoginID("tour"))
        XCTAssertTrue(app.buttons["onboarding.language.zh"].waitForExistence(timeout: 10))
        shot("tour-01-language")
        tap(app.buttons["onboarding.language.zh"])
        XCTAssertTrue(app.buttons["role.student"].waitForExistence(timeout: 10))
        shot("tour-02-role")
        tap(app.buttons["role.student"])
        XCTAssertTrue(app.buttons["signup.uiTestLogin"].waitForExistence(timeout: 10))
        shot("tour-03-signup")
        app.buttons["signup.uiTestLogin"].tap()
        XCTAssertTrue(app.buttons["home.continueTone"].waitForExistence(timeout: 15))
        shot("tour-04-home")

        tap(app.buttons["home.tone"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-06-practice-ready")
        app.buttons["practice.record"].tap()
        Thread.sleep(forTimeInterval: 0.9)
        shot("tour-07-practice-recording")
        Thread.sleep(forTimeInterval: 0.4)
        app.buttons["practice.record"].tap()
        XCTAssertTrue(app.buttons["practice.tryAgain"].waitForExistence(timeout: 10))
        shot("tour-08-practice-result")
        tap(app.buttons["practice.advice"])
        Thread.sleep(forTimeInterval: 0.8)
        shot("tour-08b-advice")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["practice.wordPicker"])
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-09-word-picker")
        app.buttons["word.heshui"].tap()
        Thread.sleep(forTimeInterval: 0.6)
        app.buttons["practice.mode.colour"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        shot("tour-10-practice-colour-mode")

        tap(app.buttons["practice.more"])
        tap(app.buttons.matching(NSPredicate(format: "label CONTAINS '自测'")).firstMatch)
        XCTAssertTrue(app.staticTexts["selfTest.progress"].waitForExistence(timeout: 10))
        shot("tour-11-self-test")
        tap(app.buttons["selfTest.exit"])
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5), "返回首页后主导航应恢复")

        tab(1)
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-12-history")
        tab(2)
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-13-settings")
        app.swipeUp()
        shot("tour-14-settings-bottom")
        tap(app.buttons["settings.help"])
        Thread.sleep(forTimeInterval: 0.8)
        shot("tour-15-help")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        tab(0)
        Thread.sleep(forTimeInterval: 0.6)
        // 练过一次之后，首页出现真实的「继续练习」
        shot("tour-05-home-with-history")
        tap(app.buttons["home.freeText"])
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-16-free-text")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app.buttons["home.aspiration"])
        Thread.sleep(forTimeInterval: 1.2)
        shot("tour-17-aspiration")
    }

    /// A14 / A15 / A24：示范 → 录音 → 回听 → 再录，连续三轮；再换词、切模式。
    /// 录音键在待录、录音中、有结果各状态下**位置和大小都不变**，两侧按钮也不动。
    ///
    /// 这里的录音是合成信号，验证的是界面状态机与播放互斥；
    /// 真实麦克风与音频会话要在真机上验。
    func testRecordButtonStaysPutAcrossStatesAndRounds() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh",
               login: newLoginID("tour-stable"))
        signIn()
        tap(app.buttons["home.tone"])
        let record = app.buttons["practice.record"]
        let listen = app.buttons["practice.listen"]
        let next = app.buttons["practice.next"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: record)
        waitForExpectations(timeout: 10)
        let home = (record.frame, listen.frame, next.frame)

        func assertUnmoved(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(record.frame, home.0, "\(state)：录音键移位了", file: file, line: line)
            XCTAssertEqual(listen.frame, home.1, "\(state)：示范键移位了", file: file, line: line)
            XCTAssertEqual(next.frame, home.2, "\(state)：下一词键移位了", file: file, line: line)
        }

        for round in 1...3 {
            listen.tap()                                   // 听示范
            Thread.sleep(forTimeInterval: 0.6)
            assertUnmoved("第 \(round) 轮 示范播放中")
            record.tap()                                   // 播放中直接开始录音：先停播放
            Thread.sleep(forTimeInterval: 0.8)
            assertUnmoved("第 \(round) 轮 录音中")
            XCTAssertFalse(listen.isEnabled, "录音时不能再播放示范")
            XCTAssertFalse(next.isEnabled, "录音时不能切词")
            XCTAssertFalse(app.buttons["practice.wordPicker"].isEnabled, "录音时不能选词")
            Thread.sleep(forTimeInterval: 0.5)
            record.tap()                                   // 停止
            XCTAssertTrue(app.buttons["practice.tryAgain"].waitForExistence(timeout: 10),
                          "第 \(round) 轮没有出结果")
            assertUnmoved("第 \(round) 轮 结果显示后")
            tap(app.buttons["practice.replay"])            // 回听
            Thread.sleep(forTimeInterval: 0.5)
            listen.tap()                                   // 回听中点示范：两者互斥，不该崩
            Thread.sleep(forTimeInterval: 0.5)
            assertUnmoved("第 \(round) 轮 回听与示范切换后")
        }
        app.buttons["practice.mode.colour"].tap()
        assertUnmoved("切到颜色模式后")
        app.buttons["practice.mode.curve"].tap()
        next.tap()
        expectation(for: enabled, evaluatedWith: record)
        waitForExpectations(timeout: 10)
        assertUnmoved("换到下一词后")
        XCTAssertTrue(app.buttons["home.tone"].exists == false, "仍在练习页")
    }

    /// 没录到声音：技术失败说明，**不是低分**；录音键原地可再点。
    func testTourTechnicalFailure() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh", audio: "silent",
               login: newLoginID("tour-silent"))
        signIn()
        tap(app.buttons["home.tone"])
        recordOnce()
        XCTAssertTrue(app.otherElements["practice.failure"].waitForExistence(timeout: 10),
                      "没录到声音应显示技术失败说明")
        XCTAssertFalse(app.buttons["practice.tryAgain"].exists, "技术失败不显示成绩区")
        shot("tour-20-practice-technical-failure")
        XCTAssertTrue(app.buttons["practice.record"].isEnabled, "技术失败后可以直接重录")
        // 没有研究配置时：研究入口不出现，本机也不积攒任何研究记录（A01）
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["home.research"].exists)
        tab(2)
        XCTAssertEqual(debugValue("participation"), "notAsked")
        XCTAssertEqual(debugValue("collecting"), "no")
        XCTAssertEqual(debugValue("pendingAttempts"), "0")
        XCTAssertEqual(debugValue("pendingEvents"), "0")
    }

    /// 四种界面语言的关键页（需求 U07 / A25）。阿拉伯语为从右到左，
    /// 但汉字、拼音、曲线与操作栏的左右顺序不镜像。
    func testTourLanguages() {
        for language in ["en", "fr", "ar"] {
            launch(reset: true, baseURL: Self.offlineURL, language: language,
                   login: newLoginID("tour-\(language)"))
            signIn()
            shot("lang-\(language)-01-home")
            tap(app.buttons["home.tone"])
            recordAndWaitForResult()
            shot("lang-\(language)-03-practice-result")
            app.buttons["practice.mode.colour"].tap()
            Thread.sleep(forTimeInterval: 0.4)
            shot("lang-\(language)-04-practice-colour")
            // 把模式换回曲线，免得影响下一轮
            app.buttons["practice.mode.curve"].tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            tab(1)
            Thread.sleep(forTimeInterval: 0.5)
            shot("lang-\(language)-05-history")
            tab(2)
            Thread.sleep(forTimeInterval: 0.5)
            shot("lang-\(language)-06-settings")
            app.terminate()
        }
    }

    /// 放大文字（辅助功能字号）下的法语关键页：长文案不截断、不盖住录音栏（A24）。
    func testTourLargeText() {
        launch(reset: true, baseURL: Self.offlineURL, language: "fr",
               login: newLoginID("tour-large"),
               contentSize: "UICTContentSizeCategoryAccessibilityL")
        signIn()
        shot("large-fr-01-home")
        tap(app.buttons["home.tone"])
        recordAndWaitForResult()
        shot("large-fr-02-practice-result")
        XCTAssertTrue(app.buttons["practice.record"].isHittable, "放大文字后录音键仍可点")
        XCTAssertTrue(app.buttons["practice.listen"].isHittable)
        XCTAssertTrue(app.buttons["practice.next"].isHittable)
    }

    /// 深色外观：语义色自动切换，不出现白底白字。
    func testTourDarkAppearance() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh",
               login: newLoginID("tour-dark"), appearance: "dark")
        signIn()
        shot("dark-01-home")
        tap(app.buttons["home.tone"])
        recordAndWaitForResult()
        shot("dark-02-practice-result")
        app.buttons["practice.mode.colour"].tap()
        Thread.sleep(forTimeInterval: 0.4)
        shot("dark-03-practice-colour")
        app.buttons["practice.mode.curve"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        tab(2)
        Thread.sleep(forTimeInterval: 0.5)
        shot("dark-04-settings")
    }
}

/// 横屏。App 声明支持横屏，所以至少要能登录、进首页、进练习页并录一次。
@MainActor
final class LandscapeUITests: PinYintoneUITestCase {

    override func tearDown() async throws {
        XCUIDevice.shared.orientation = .portrait
        try await super.tearDown()
    }

    func testAppIsUsableInLandscape() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh", login: newLoginID("landscape"))
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)
        shot("landscape-01-role")
        signIn()
        shot("landscape-02-home")
        tap(app.buttons["home.tone"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10))
        shot("landscape-03-practice")
        recordAndWaitForResult()
        shot("landscape-04-result")
    }
}
