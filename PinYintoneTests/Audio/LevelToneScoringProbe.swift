import XCTest
@testable import PinYintone

/// 平调词（一声）评分方向的回归测试。
///
/// 背景：纯 z-score 对平调是退化的——一声词真实起伏只有几 Hz，除以接近零的 SD
/// 会把微观抖动放大成满量程，导致**读得越平分数越差、读成下滑反而通关**。
/// 已通过「带下限的 z-score」修复，详见 `docs/LEVEL_TONE_SCORING.md`。
/// 以下断言守住修复后的正确方向，防止回归。
final class LevelToneScoringProbe: XCTestCase {
    private let f0 = F0Extractor()
    private let dtw = DTWAnalyzer()

    /// 两音节轮廓：每音节 start→end，整词再叠加 wordDrop 的下倾
    private func syl2(start: Float, end: Float, wordDrop: Float,
                      jitter: Float = 1, n: Int = 24) -> [Float] {
        var out: [Float] = []
        for s in 0..<2 {
            for i in 0..<n {
                let t = Float(i) / Float(n - 1)
                let k = Float(s * n + i) / Float(2 * n - 1)
                out.append(start + (end - start) * t - wordDrop * k
                           + (Float((s * n + i) % 3) - 1) * jitter)
            }
        }
        return out
    }

    private func score(_ tones: [Int], _ cand: [Float]) -> Float {
        dtw.distance(reference: f0.normalize(ToneContour.ideal(for: tones)),
                     candidate: f0.normalize(cand))
    }

    /// 一声词：读平（正确）必须优于读成下滑（错误）
    func testLevelToneRewardsLevelPitch() {
        let flat    = score([1, 1], syl2(start: 268, end: 264, wordDrop: 0))
        let falling = score([1, 1], syl2(start: 268, end: 264, wordDrop: 45))

        XCTAssertLessThan(flat, 0.5, "读平（正确）应通关，DTW=\(flat)")
        XCTAssertLessThan(flat, falling,
            "正确发音分数必须优于错误发音（历史缺陷：曾经是反的）")
    }

    /// 归一化除数下限必须与音域成比例：同一形状换音域，分数不得改变。
    /// 固定 Hz 下限会重新引入说话人依赖，与 per-utterance 归一化的目的冲突。
    func testScoringIsSpeakerRangeIndependent() {
        for scale in [Float(0.45), 1.0, 1.32] {      // ~120Hz / ~265Hz / ~350Hz
            let cand = syl2(start: 268, end: 264, wordDrop: 0).map { $0 * scale }
            let ref = ToneContour.ideal(for: [1, 1]).map { $0 * scale }
            let d = dtw.distance(reference: f0.normalize(ref), candidate: f0.normalize(cand))
            XCTAssertEqual(d, 0.151, accuracy: 0.01, "音域 x\(scale) 分数应一致，实得 \(d)")
        }
    }

    /// 高方差声调（有真实走势）不受下限影响，分数与改动前一致
    func testHighVarianceTonesUnaffectedByFloor() {
        let d = score([4, 4], syl2(start: 285, end: 140, wordDrop: 0))
        XCTAssertEqual(d, 0.081, accuracy: 0.005,
                       "4+4 的 SD 远大于下限，除数不变，分数应与改动前逐位一致")
    }

    /// 对照：去声词方向正常，说明问题只出在低方差的平调
    func testFallingToneScoringIsCorrect() {
        let correct = score([4, 4], syl2(start: 285, end: 140, wordDrop: 0))
        let wrongFlat = score([4, 4], syl2(start: 265, end: 265, wordDrop: 0))
        XCTAssertLessThan(correct, 0.5, "4+4 正确急降应通关")
        XCTAssertGreaterThan(wrongFlat, 0.5, "4+4 错误平读应不通关")
    }
}
