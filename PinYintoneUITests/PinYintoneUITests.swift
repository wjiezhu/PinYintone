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
        app.swipeUp()
        shot("tour-05-home-bottom")
        app.swipeDown()

        tap(app.buttons["home.continueTone"])
        XCTAssertTrue(app.buttons["practice.record"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable, "练习页只留一条操作栏，主导航应收起")
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
        app.segmentedControls.buttons.element(boundBy: 0).tap()
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
        app.swipeUp()
        tap(app.buttons["home.freeText"])
        Thread.sleep(forTimeInterval: 0.6)
        shot("tour-16-free-text")
    }

    /// 没录到声音：琥珀色的技术失败说明，**不是低分**；录音键原地可再点。
    func testTourTechnicalFailure() {
        launch(reset: true, baseURL: Self.offlineURL, language: "zh", audio: "silent",
               login: newLoginID("tour-silent"))
        signIn()
        tap(app.buttons["home.continueTone"])
        recordOnce()
        XCTAssertTrue(app.otherElements["practice.failure"].waitForExistence(timeout: 10),
                      "没录到声音应显示技术失败说明")
        XCTAssertFalse(app.buttons["practice.tryAgain"].exists, "技术失败不显示成绩区")
        shot("tour-20-practice-technical-failure")
        XCTAssertTrue(app.buttons["practice.record"].isEnabled, "技术失败后可以直接重录")
    }

    /// 四种界面语言的关键页（需求 U07 / A25）。阿拉伯语为从右到左，
    /// 但汉字、拼音、曲线与操作栏的左右顺序不镜像。
    func testTourLanguages() {
        for language in ["en", "fr", "ar"] {
            launch(reset: true, baseURL: Self.offlineURL, language: language,
                   login: newLoginID("tour-\(language)"))
            signIn()
            shot("lang-\(language)-01-home")
            app.swipeUp()
            shot("lang-\(language)-02-home-bottom")
            app.swipeDown()
            tap(app.buttons["home.continueTone"])
            recordAndWaitForResult()
            shot("lang-\(language)-03-practice-result")
            app.segmentedControls.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 0.4)
            shot("lang-\(language)-04-practice-colour")
            // 把模式换回曲线，免得影响下一轮
            app.segmentedControls.buttons.element(boundBy: 1).tap()
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
        tap(app.buttons["home.continueTone"])
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
        app.swipeUp()
        shot("dark-01b-home-bottom")
        app.swipeDown()
        tap(app.buttons["home.continueTone"])
        recordAndWaitForResult()
        shot("dark-02-practice-result")
        app.segmentedControls.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.4)
        shot("dark-03-practice-colour")
        app.segmentedControls.buttons.element(boundBy: 1).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        tab(2)
        Thread.sleep(forTimeInterval: 0.5)
        shot("dark-04-settings")
    }
}
