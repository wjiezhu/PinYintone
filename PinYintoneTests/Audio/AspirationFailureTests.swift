import XCTest
@testable import PinYintone

/// 送气练习（关卡 1）的技术失败处理。
///
/// 关卡 2、3 都修过同类问题，关卡 1 一直没查：
/// - 录音起不来只设 isRecording = false，**无任何提示**（禁令 11）
/// - 没录上时照样落一条 triggerRate = 0 / passed = false 的记录——
///   等于把麦克风故障算成「送气没做到」（禁令 9）
@MainActor
final class AspirationFailureTests: XCTestCase {

    /// 一帧都没收到时 stop() **不得落发音记录**，而是给出重录提示
    func testNoFramesProducesHintNotScore() {
        let vm = AspirationViewModel()
        let before = AspirationRepository.shared.fetchAll().count
        vm.stop()      // 从未开始检测，receivedFrames = 0
        XCTAssertNotNil(vm.retryHint, "没录上必须给出可执行提示，不得静默")
        XCTAssertEqual(AspirationRepository.shared.fetchAll().count, before,
                       "技术失败不得计入发音成绩（禁令 9）")
    }

    /// 提示文案四语齐备
    func testRetryCopyLocalized() throws {
        for lang in ["zh-Hans", "en", "fr", "ar"] {
            let b = try XCTUnwrap(Bundle(path: try XCTUnwrap(
                Bundle.main.path(forResource: lang, ofType: "lproj"))))
            for k in ["tone_retry_mic_unavailable", "tone_retry_no_voice"] {
                XCTAssertNotEqual(b.localizedString(forKey: k, value: nil, table: nil), k,
                                  "\(lang) 缺 \(k)")
            }
        }
    }

    /// 通关线仍为 CLAUDE.md 锁定的 0.6，本次改动不得动它
    func testPassThresholdUnchanged() {
        let d = AspirationDetector()
        let allOn = [[Float]](repeating: [Float](repeating: 1, count: 1600), count: 6)
        XCTAssertGreaterThanOrEqual(d.triggerRate(frames: allOn), 0.6)
    }
}
