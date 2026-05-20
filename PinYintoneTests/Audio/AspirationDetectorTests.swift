import XCTest
@testable import PinYintone

final class AspirationDetectorTests: XCTestCase {
    var detector: AspirationDetector!

    override func setUp() {
        super.setUp()
        detector = AspirationDetector()
    }

    override func tearDown() {
        detector = nil
        super.tearDown()
    }

    /// 常数值帧：RMS = |value|，便于推算 dB
    private func constantFrame(_ value: Float, count: Int = 1600) -> [Float] {
        [Float](repeating: value, count: count)
    }

    func testBaselineCalibration() {
        // 常数 0.01 → RMS 0.01 → 20·log10(0.01) = -40 dB
        detector.calibrateBaseline(frames: [constantFrame(0.01), constantFrame(0.01)])
        XCTAssertEqual(detector.baselineDB, -40, accuracy: 0.5, "底噪 dB 计算应正确")
        XCTAssertEqual(detector.thresholdDB, -25, accuracy: 0.5, "阈值 = 底噪 + 15 dB")
    }

    func testTriggerAboveThreshold() {
        detector.calibrateBaseline(frames: [constantFrame(0.01)])   // 底噪 -40，阈值 -25
        let value = 0.01 * powf(10, 16.0 / 20.0)                     // 底噪 + 16 dB
        XCTAssertTrue(detector.detect(frame: constantFrame(value)), "+16 dB 应触发")
    }

    func testNoTriggerBelowThreshold() {
        detector.calibrateBaseline(frames: [constantFrame(0.01)])
        let value = 0.01 * powf(10, 14.0 / 20.0)                     // 底噪 + 14 dB
        XCTAssertFalse(detector.detect(frame: constantFrame(value)), "+14 dB 不应触发")
    }

    func testTriggerRatePassAt0_6() {
        detector.calibrateBaseline(frames: [constantFrame(0.01)])
        let hi = constantFrame(0.01 * powf(10, 16.0 / 20.0))         // 触发
        let lo = constantFrame(0.01 * powf(10, 14.0 / 20.0))         // 不触发
        let frames = [hi, hi, hi, lo, lo]                           // 3/5 = 0.6
        XCTAssertEqual(detector.triggerRate(frames: frames), 0.6, accuracy: 1e-5,
                       "60% 触发帧 → triggerRate == 0.6")
    }

    func testTriggerRateFailBelow0_6() {
        detector.calibrateBaseline(frames: [constantFrame(0.01)])
        let hi = constantFrame(0.01 * powf(10, 16.0 / 20.0))
        let lo = constantFrame(0.01 * powf(10, 14.0 / 20.0))
        let frames = [hi, hi, lo, lo, lo]                           // 2/5 = 0.4
        XCTAssertLessThan(detector.triggerRate(frames: frames), 0.6, "低于 60% 不通关")
    }

    func testEmptyFramesTriggerRateZero() {
        detector.calibrateBaseline(frames: [constantFrame(0.01)])
        XCTAssertEqual(detector.triggerRate(frames: []), 0)
    }
}
