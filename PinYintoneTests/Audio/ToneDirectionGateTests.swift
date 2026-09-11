import XCTest
@testable import PinYintone

/// 平调词走向闸门。背景见 `docs/LEVEL_TONE_SCORING.md`：
/// DTW 在 z-score 下判不出全一声的词被读成一路下滑，闸门在半音标度上补判。
final class ToneDirectionGateTests: XCTestCase {

    /// 两音节轨迹（原始 Hz）：每音节 268→264，整词再叠加 wordDrop
    private func track(wordDrop: Float, n: Int = 24) -> [Float] {
        var out: [Float] = []
        for s in 0..<2 {
            for i in 0..<n {
                let t = Float(i) / Float(n - 1)
                let k = Float(s * n + i) / Float(2 * n - 1)
                out.append(268 + (264 - 268) * t - wordDrop * k)
            }
        }
        return out
    }

    // MARK: - 适用范围

    func testOnlyAppliesToAllLevelWords() {
        XCTAssertTrue(ToneDirectionGate.applies(tones: [1, 1]))
        XCTAssertTrue(ToneDirectionGate.applies(tones: [1]))
        XCTAssertFalse(ToneDirectionGate.applies(tones: [1, 4]), "含非一声不适用")
        XCTAssertFalse(ToneDirectionGate.applies(tones: [4, 4]))
        XCTAssertFalse(ToneDirectionGate.applies(tones: []), "无声调信息不适用")
    }

    func testNonLevelWordsAreNeverGated() {
        // 4+4 本就该大幅下行，绝不能被闸门误伤
        let steepFall = (0..<48).map { Float(285) - 145 * Float($0) / 47 }
        XCTAssertNil(ToneDirectionGate.fallSemitones(hzTrack: steepFall, tones: [4, 4]))
        XCTAssertFalse(ToneDirectionGate.fails(hzTrack: steepFall, tones: [4, 4]))
    }

    // MARK: - 判定

    func testIdealLevelContourPasses() {
        // 理想 T1 轮廓自身（-0.27 半音）必须放行，且余量要大
        let ideal = ToneContour.ideal(for: [1, 1])
        let fall = ToneDirectionGate.fallSemitones(hzTrack: ideal, tones: [1, 1])
        XCTAssertNotNil(fall)
        XCTAssertGreaterThan(fall!, -1, "理想轮廓落差应远小于阈值，实得 \(fall!)")
        XCTAssertFalse(ToneDirectionGate.fails(hzTrack: ideal, tones: [1, 1]))
    }

    func testNaturalDeclinationPasses() {
        // 自然句调下倾（≈1 半音）不应被拦
        XCTAssertFalse(ToneDirectionGate.fails(hzTrack: track(wordDrop: 20), tones: [1, 1]))
    }

    func testGrossFallIsGated() {
        // 这正是 DTW 判不出来的那一档：降 80Hz ≈ -4.3 半音
        XCTAssertTrue(ToneDirectionGate.fails(hzTrack: track(wordDrop: 80), tones: [1, 1]))
    }

    func testGateIsSpeakerRangeIndependent() {
        // 半音是对数比：同一形状换音域，落差应完全一致
        let base = track(wordDrop: 60)
        let low = base.map { $0 * 0.45 }      // ~120 Hz 男声
        let high = base.map { $0 * 1.32 }     // ~350 Hz 童声
        let f0 = ToneDirectionGate.fallSemitones(hzTrack: base, tones: [1, 1])!
        for t in [low, high] {
            let f = ToneDirectionGate.fallSemitones(hzTrack: t, tones: [1, 1])!
            XCTAssertEqual(f, f0, accuracy: 0.01, "换音域不应改变半音落差")
        }
    }

    func testUnvoicedFramesIgnoredAndShortTracksSkipped() {
        var withGaps = track(wordDrop: 80)
        withGaps[10] = 0; withGaps[11] = 0
        XCTAssertTrue(ToneDirectionGate.fails(hzTrack: withGaps, tones: [1, 1]),
                      "0 帧应被忽略，不影响判定")
        XCTAssertNil(ToneDirectionGate.fallSemitones(hzTrack: [265, 0, 262], tones: [1, 1]),
                     "有声帧太少应返回 nil 而非瞎判")
    }
}
