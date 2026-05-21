import XCTest

final class PinYintoneUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 全新安装启动 → 应进入引导页并显示麦克风授权按钮。
    @MainActor
    func testLaunchesIntoOnboarding() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertEqual(app.state, .runningForeground, "App 应正常启动到前台")

        let allowMic = app.buttons["onboarding.allowMic"]
        XCTAssertTrue(allowMic.waitForExistence(timeout: 15),
                      "首启应停在引导页（麦克风授权按钮可见）")
    }

    /// 启动性能基线。
    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
