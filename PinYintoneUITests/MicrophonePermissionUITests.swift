import XCTest

/// 麦克风权限（需求 R02、验收 A16）。走的是**真实录音通路**，不是合成信号。
///
/// 权限状态由运行前的脚本用 `xcrun simctl privacy` 设好，并通过 `PT_MIC_STATE` 告诉用例
/// 现在是哪种状态；没给就跳过并说明原因。三种状态各跑一次：
///
///     xcrun simctl privacy <udid> reset  microphone Joy.PinYintone   # PT_MIC_STATE=undetermined
///     xcrun simctl privacy <udid> revoke microphone Joy.PinYintone   # PT_MIC_STATE=denied
///     xcrun simctl privacy <udid> grant  microphone Joy.PinYintone   # PT_MIC_STATE=granted
///
/// 模拟器的麦克风来自宿主机，这里只验证权限流程与录音引擎能否启动；
/// 真实设备上的音频会话、播放与录音切换仍须真机验收。
@MainActor
final class MicrophonePermissionUITests: PinYintoneUITestCase {

    private func requireState(_ wanted: String) throws {
        let state = ProcessInfo.processInfo.environment["PT_MIC_STATE"] ?? ""
        try XCTSkipUnless(state == wanted, "PT_MIC_STATE 不是 \(wanted)：本用例未执行")
    }

    private func openPractice(reset: Bool) {
        launch(reset: reset, baseURL: Self.offlineURL, language: "fr", audio: "off",
               login: newLoginID("mic"))
        signIn()
        tap(app.buttons["home.tone"])
        let record = app.buttons["practice.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: record)
        waitForExpectations(timeout: 15)
    }

    /// 还没问过权限：进 App、选语言、登录、打开练习页都**不弹**权限框；
    /// 第一次点录音时先用所选语言说明用途，再弹系统授权框。
    func testPermissionIsRequestedAtFirstRecordingWithAnExplanation() throws {
        try requireState("undetermined")
        openPractice(reset: true)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "打开练习页时不该已经弹出权限框")

        app.buttons["practice.record"].tap()
        XCTAssertTrue(app.buttons["mic.allow"].waitForExistence(timeout: 5),
                      "首次录音前应先说明麦克风用途")
        shot("mic-01-explanation-fr")
        app.buttons["mic.allow"].tap()
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "说明之后才是系统授权框")
        shot("mic-02-system-prompt")
        // 允许：系统框上靠后的那个按钮
        alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        // 授权后直接开始录：录音键变成停止
        let stopLabel = NSPredicate(format: "label CONTAINS[c] 'Arr'")
        expectation(for: stopLabel, evaluatedWith: app.buttons["practice.record"])
        waitForExpectations(timeout: 10)
        shot("mic-03-recording-after-grant")
        app.buttons["practice.record"].tap()
    }

    /// 权限被拒：练习页给出说明和「打开设置」，不是一个按了没反应的按钮，也不是低分。
    func testDeniedPermissionShowsARecoveryEntry() throws {
        try requireState("denied")
        openPractice(reset: true)
        app.buttons["practice.record"].tap()
        XCTAssertTrue(app.buttons["practice.openSettings"].waitForExistence(timeout: 10),
                      "A16：麦克风被拒时应有去系统设置的入口")
        XCTAssertFalse(app.buttons["practice.tryAgain"].exists, "不显示成绩区")
        XCTAssertTrue(app.buttons["practice.record"].isEnabled, "录音键仍可点（恢复后直接重试）")
        shot("mic-04-denied-recovery-entry")
    }

    /// 在系统设置里恢复权限之后：不用重装，回到 App 就能录——录音引擎能启动。
    func testRecordingWorksAfterPermissionIsRestored() throws {
        try requireState("granted")
        // 每个用例结束后 App 都会被清回未登录状态，所以这里重新登录；
        // 系统里的麦克风权限不随 App 状态重置而变
        openPractice(reset: true)
        let record = app.buttons["practice.record"]
        record.tap()
        let stopLabel = NSPredicate(format: "label CONTAINS[c] 'Arr'")
        expectation(for: stopLabel, evaluatedWith: record)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["practice.openSettings"].exists)
        Thread.sleep(forTimeInterval: 1.5)
        record.tap()
        // 模拟器里录到的多半是静音：结果或「没录到声音」都算引擎正常收尾，
        // 只要不是权限失败、也没有卡在分析中
        let settled = NSPredicate { _, _ in
            self.app.buttons["practice.tryAgain"].exists
                || self.app.descendants(matching: .any)["practice.failure"].exists
        }
        expectation(for: settled, evaluatedWith: nil)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(app.buttons["practice.openSettings"].exists, "恢复权限后不应再提示去设置")
        shot("mic-05-after-restore")
    }
}
