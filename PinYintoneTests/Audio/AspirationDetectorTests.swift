import XCTest
@testable import Pinyintone

final class AspirationDetectorTests: XCTestCase {
    var detector: AspirationDetector!

    override func setUp() {
        super.setUp()
        detector = AspirationDetector()
    }

    func testBaselineCalibration() {
        // 送入 500 ms 静音帧（RMS ≈ 0），校验 baselineDB 计算正确
        fatalError("TODO: 实现")
    }

    func testTriggerAboveThreshold() {
        // 底噪 + 16 dB 的帧应触发（> +15 dB 阈值）
        fatalError("TODO: 实现")
    }

    func testNoTriggerBelowThreshold() {
        // 底噪 + 14 dB 的帧不应触发（< +15 dB 阈值）
        fatalError("TODO: 实现")
    }

    func testTriggerRatePassAt0_6() {
        // 60% 触发帧 → triggerRate() == 0.6（通关边界）
        fatalError("TODO: 实现")
    }

    func testTriggerRateFailBelow0_6() {
        // 59% 触发帧 → triggerRate() < 0.6（不通关）
        fatalError("TODO: 实现")
    }
}
