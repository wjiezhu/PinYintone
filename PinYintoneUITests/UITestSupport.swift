import XCTest

/// 界面测试的公共脚手架。
///
/// 这些测试驱动的是**真实 App 界面**，后端指向本地测试服务（或一个不通的地址，
/// 用来模拟断网）。它们依赖开发构建里的几个启动开关（见 App 里的 `UITestSupport`）：
/// 测试登录、合成录音信号、状态重置。正式构建里这些开关不存在。
///
/// 运行方式：先起本地后端并冻结一份与当前构建号匹配的测试配置，然后
///
///     TEST_RUNNER_PT_API_BASE_URL=http://127.0.0.1:8765 \
///     TEST_RUNNER_PT_SHOT_DIR=/tmp/shots \
///     xcodebuild test -only-testing:PinYintoneUITests ...
///
/// 没给 `PT_API_BASE_URL` 时，需要后端的用例会**跳过并说明原因**，不会假装通过。
@MainActor
class PinYintoneUITestCase: XCTestCase {

    var app: XCUIApplication!
    /// 本次测试用的账号标识。每个用例一个，后端据此能找到对应的参与者。
    private(set) var loginID = ""

    /// 一个肯定连不上的地址：用来模拟断网、超时
    static let offlineURL = "http://127.0.0.1:9"

    static var backendURL: String? {
        ProcessInfo.processInfo.environment["PT_API_BASE_URL"]
    }
    static var shotDirectory: String? {
        ProcessInfo.processInfo.environment["PT_SHOT_DIR"]
    }
    /// 一次完整运行的批次号，写进账号标识里，便于事后在库里按批次核对
    static let runID: String = ProcessInfo.processInfo.environment["PT_RUN_ID"]
        ?? String(Int(Date().timeIntervalSince1970))

    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // 别的用例（系统模板的启动截图）会把模拟器转成横屏留在那里
        XCUIDevice.shared.orientation = .portrait
    }

    /// 每个用例结束后把 App 清回「全新安装、未登录」，并且**不留任何未同步的记录**。
    ///
    /// 这一步不是洁癖：离线用例会在本机留下没传出去的练习记录。之后只要有人不带测试地址
    /// 启动这个 App（手动点开、跑单元测试、系统模板的启动截图），自动同步就会把它们
    /// 传到 `APIConfig.plist` 里配置的线上后端。2026-10-13 实际发生过，所以在这里堵死。
    override func tearDown() async throws {
        app.terminate()
        let cleaner = XCUIApplication()
        cleaner.launchEnvironment = ["PT_API_BASE_URL": Self.offlineURL, "PT_UITEST_RESET": "1"]
        cleaner.launch()
        cleaner.terminate()
        try await super.tearDown()
    }

    func requireBackend(file: StaticString = #filePath, line: UInt = #line) throws -> String {
        try XCTUnwrap(Self.backendURL.flatMap { $0.isEmpty ? nil : $0 },
                      "未提供 PT_API_BASE_URL：本用例需要本地测试后端，未执行", file: file, line: line)
    }

    /// 启动 App。
    /// - Parameters:
    ///   - reset: 清空本机全部状态，相当于全新安装
    ///   - baseURL: 后端地址；传 `offlineURL` 模拟断网
    ///   - language: 直接设定界面语言并跳过语言选择页；nil 则走真实的语言选择
    ///   - audio: 合成录音信号。match = 有效发音；silent = 没录到声音
    ///   - appearance: "dark" 固定为深色外观（截深色界面用）；nil 跟随系统
    func launch(reset: Bool, baseURL: String, language: String? = nil,
                audio: String = "match", login: String? = nil,
                contentSize: String? = nil, appearance: String? = nil) {
        if let login { loginID = login }
        var env = ["PT_API_BASE_URL": baseURL,
                   "PT_SYNTHETIC_AUDIO": audio,
                   "PT_UITEST_LOGIN": loginID]
        if reset { env["PT_UITEST_RESET"] = "1" }
        if let language { env["PT_UITEST_LANGUAGE"] = language }
        if let appearance { env["PT_UITEST_APPEARANCE"] = appearance }
        app.launchEnvironment = env
        app.launchArguments = contentSize.map {
            ["-UIPreferredContentSizeCategoryName", $0]
        } ?? []
        app.launch()
    }

    func relaunch(baseURL: String, audio: String = "match") {
        app.terminate()
        launch(reset: false, baseURL: baseURL, audio: audio)
    }

    func newLoginID(_ name: String) -> String {
        "uitest-\(Self.runID)-\(name)"
    }

    // MARK: - 常用步骤

    /// 语言选择 → 学生 → 测试登录，停在练习首页
    /// `keepConsentPopup` 为 false 时关掉登录后弹出的研究说明，停在首页（状态仍是「未询问」）
    func signIn(chooseLanguage: String? = nil, keepConsentPopup: Bool = false,
                file: StaticString = #filePath, line: UInt = #line) {
        if let chooseLanguage {
            tap(app.buttons["onboarding.language.\(chooseLanguage)"], file: file, line: line)
        }
        tap(app.buttons["role.student"], file: file, line: line)
        let login = app.buttons["signup.uiTestLogin"]
        XCTAssertTrue(login.waitForExistence(timeout: 10), "登录页没有出现", file: file, line: line)
        if !login.isHittable { app.swipeUp() }
        login.tap()
        XCTAssertTrue(app.buttons["home.continueTone"].waitForExistence(timeout: 15),
                      "登录后应直接进入练习首页", file: file, line: line)
        if !keepConsentPopup, app.buttons["consent.decline"].waitForExistence(timeout: 4) {
            tap(app.buttons["research.close"], file: file, line: line)
        }
    }

    func tap(_ element: XCUIElement, timeout: TimeInterval = 10,
             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "找不到 \(element)", file: file, line: line)
        if !element.isHittable {
            app.swipeUp()
        }
        element.tap()
    }

    func tab(_ index: Int) {
        app.tabBars.buttons.element(boundBy: index).tap()
    }

    /// 录一次：点录音 → 等合成信号放完 → 再点一次停止
    func recordOnce(file: StaticString = #filePath, line: UInt = #line) {
        let record = app.buttons["practice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10), file: file, line: line)
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: record)
        waitForExpectations(timeout: 10)
        record.tap()
        Thread.sleep(forTimeInterval: 1.3)
        record.tap()
    }

    /// 录一次并等到本次结果出现
    func recordAndWaitForResult(file: StaticString = #filePath, line: UInt = #line) {
        recordOnce(file: file, line: line)
        XCTAssertTrue(app.buttons["practice.tryAgain"].waitForExistence(timeout: 10),
                      "录音后没有出现本次结果", file: file, line: line)
    }

    /// 问卷：选一个选项
    func choose(_ code: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(app.buttons["survey.option.\(code)"], file: file, line: line)
    }

    func surveyNext() { tap(app.buttons["survey.next"]) }
    func surveySkip() { tap(app.buttons["survey.skip"]) }
    func surveySubmit() { tap(app.buttons["survey.submit"]) }

    /// 打开知情说明并同意
    func agreeToConsent(file: StaticString = #filePath, line: UInt = #line) {
        let agree = app.buttons["consent.agree"]
        XCTAssertTrue(agree.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertFalse(agree.isEnabled, "未勾选之前「同意」不可点——不默认勾选", file: file, line: line)
        let toggle = app.switches["consent.toggle"]
        // 开关在说明的最末尾。要滚到它**整个**露在底部按钮栏之上再点：
        // 只露出一半时 isHittable 也是 true，点下去会落在按钮栏的「暂不参加」上。
        let barTop = agree.frame.minY
        for _ in 0..<8 where !toggle.exists || toggle.frame.maxY > barTop - 8 { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertLessThan(toggle.frame.maxY, barTop, "同意开关应能滚到按钮栏之上",
                          file: file, line: line)
        // SwiftUI 的 Toggle：点整行不一定切换，点右侧的开关本体
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(agree.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(agree.isEnabled, "勾选后应可同意", file: file, line: line)
        agree.tap()
    }

    /// 背景表：成年、摩洛哥、给定课程阶段；其余两题跳过
    func answerBackground(adult: String = "adult", nationality: String? = "MA",
                          stage: String? = "hsk2") {
        choose(adult); surveyNext()
        if let nationality { choose(nationality); surveyNext() } else { surveySkip() }
        if let stage { choose(stage); surveyNext() } else { surveySkip() }
        surveySkip()          // B04
        surveySkip()          // B05：最后一题，跳过即提交
    }

    /// 设置页调试区里的一项（仅开发构建有），形如 "participation=enrolled"
    func debugValue(_ name: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = app.staticTexts["debug.\(name)"]
        for _ in 0..<8 where !element.exists { app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "调试项 \(name) 不存在",
                      file: file, line: line)
        return element.label.components(separatedBy: "=").last ?? ""
    }

    /// 等到调试项变成期望值（上传是异步的）
    func waitForDebug(_ name: String, toEqual expected: String, timeout: TimeInterval = 20,
                      file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < deadline {
            last = debugValue(name, file: file, line: line)
            if last == expected { return }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("\(name) 期望 \(expected)，实际 \(last)", file: file, line: line)
    }

    // MARK: - 截图

    /// 截一张当前界面。作为测试附件保留；给了 PT_SHOT_DIR 时同时写成 PNG 文件。
    func shot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = Self.shotDirectory {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: dir)
                .appendingPathComponent("\(name).png"))
        }
    }
}
