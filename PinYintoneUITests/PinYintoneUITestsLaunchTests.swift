//
//  PinYintoneUITestsLaunchTests.swift
//  PinYintoneUITests
//
//  Created by zhouo on 18/5/2026.
//

import XCTest

final class PinYintoneUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        // 启动截图也必须带测试地址并清空本机状态：不带的话 App 连的是线上后端，
        // 启动时的自动同步会把本机残留的测试记录传上去。
        app.launchEnvironment = ["PT_API_BASE_URL": "http://127.0.0.1:9", "PT_UITEST_RESET": "1"]
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
