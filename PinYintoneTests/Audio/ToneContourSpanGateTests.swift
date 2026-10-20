import XCTest
@testable import PinYintone

/// 非一声词的走势幅度闸门。背景见 `docs/SCORING_FLAT_READING_STUDY.md`：
/// 归一化尺度不变，读平的录音照样能和参照形状对上，闸门在半音标度上补判。
final class ToneContourSpanGateTests: XCTestCase {

    /// 线性从 startHz 走到 startHz × 2^(semitones/12)，n 帧
    private func ramp(_ startHz: Float, semitones: Float, n: Int = 48) -> [Float] {
        (0..<n).map { startHz * Float(pow(2, Double(semitones) * Double($0) / Double(n - 1) / 12)) }
    }

    // MARK: - 适用范围（与走向闸门不重叠）

    func testAppliesOnlyToWordsWithTone234() {
        XCTAssertTrue(ToneContourSpanGate.applies(tones: [4, 4]))
        XCTAssertTrue(ToneContourSpanGate.applies(tones: [1, 3]))
        XCTAssertTrue(ToneContourSpanGate.applies(tones: [4, 5]))
        XCTAssertFalse(ToneContourSpanGate.applies(tones: [1, 1]), "全一声归走向闸门")
        XCTAssertFalse(ToneContourSpanGate.applies(tones: [1, 5]), "1+5 两道闸门都不管")
        XCTAssertFalse(ToneContourSpanGate.applies(tones: []))
        for tones in [[1, 1], [1], [1, 5], [4, 4], [2, 3], [1, 4]] {
            XCTAssertFalse(ToneContourSpanGate.applies(tones: tones) && ToneDirectionGate.applies(tones: tones),
                           "\(tones)：两道闸门不得同时适用")
        }
    }

    // MARK: - 跨度计算

    func testSpanIsRegisterIndependent() throws {
        // 同一形状、不同音域：半音是对数比，结果相同
        let male = try XCTUnwrap(ToneContourSpanGate.spanSemitones(hzTrack: ramp(120, semitones: -8)))
        let female = try XCTUnwrap(ToneContourSpanGate.spanSemitones(hzTrack: ramp(260, semitones: -8)))
        XCTAssertEqual(male, female, accuracy: 1e-3)
        XCTAssertEqual(male, 6.4, accuracy: 0.2, "P90−P10 约为全程的 80%")
    }

    func testSpanIgnoresUnvoicedFramesAndIsDurationIndependent() throws {
        let short = try XCTUnwrap(ToneContourSpanGate.spanSemitones(hzTrack: ramp(200, semitones: 5, n: 24)))
        let long = try XCTUnwrap(ToneContourSpanGate.spanSemitones(
            hzTrack: [0, 0] + ramp(200, semitones: 5, n: 120) + [0, 0, 0]))
        XCTAssertEqual(short, long, accuracy: 0.15)
    }

    func testTooFewVoicedFramesGivesNil() {
        XCTAssertNil(ToneContourSpanGate.spanSemitones(hzTrack: [0, 200, 210, 0, 220, 230, 240]))
        XCTAssertNotNil(ToneContourSpanGate.spanSemitones(hzTrack: [200, 210, 220, 230, 240, 250]))
        XCTAssertFalse(ToneContourSpanGate.fails(hzTrack: [220, 220, 220, 0, 0], tones: [4, 4]),
                       "算不出跨度时不拦（有声帧不足另由技术重录处理）")
    }

    func testOctaveSpikeDoesNotInflateSpan() throws {
        // 读平 + 两个八度错误帧：P90−P10 不受个别帧影响
        var flat = [Float](repeating: 220, count: 60)
        flat[10] = 440; flat[30] = 110
        let span = try XCTUnwrap(ToneContourSpanGate.spanSemitones(hzTrack: flat))
        XCTAssertLessThan(span, 0.01)
    }

    // MARK: - 判定

    func testFlatReadingOfFallingWordFails() {
        // t4t4_read_flat 的情形：220 Hz 平读，外加 1 个半音的自然下倾
        XCTAssertTrue(ToneContourSpanGate.fails(hzTrack: ramp(220, semitones: -1), tones: [4, 4]))
        XCTAssertTrue(ToneContourSpanGate.fails(hzTrack: ramp(220, semitones: 0), tones: [2, 4]))
    }

    func testRealContoursPass() {
        // 理想轮廓本身（Hz）：每个含二 / 三 / 四声的组合都远超下限
        for tones in [[4, 4], [2, 2], [3, 1], [3, 2], [2, 1], [4, 5], [1, 4], [3, 4]] {
            XCTAssertFalse(ToneContourSpanGate.fails(hzTrack: ToneContour.ideal(for: tones), tones: tones),
                           "\(tones) 理想轮廓不应被拦")
        }
        // 走势压缩到约 3 个半音（读得不到位，但有起伏）：放行，交给 DTW
        XCTAssertFalse(ToneContourSpanGate.fails(hzTrack: ramp(220, semitones: -3.6), tones: [4, 4]))
    }

    func testLevelWordsAreNeverGatedForBeingFlat() {
        // 一声词读平是对的
        XCTAssertFalse(ToneContourSpanGate.fails(hzTrack: ramp(266, semitones: 0), tones: [1, 1]))
        XCTAssertFalse(ToneContourSpanGate.fails(hzTrack: ramp(266, semitones: 0), tones: [1, 5]))
    }
}
