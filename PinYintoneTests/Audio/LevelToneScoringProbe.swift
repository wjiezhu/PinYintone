import XCTest
@testable import PinYintone

/// **特征测试（characterization test）**：固化当前平调词评分反向的缺陷。
///
/// 这里断言的是**现状而非期望**——一声词读得越平分数越差，读成下滑反而通关。
/// 详见 `docs/LEVEL_TONE_SCORING.md`。
/// ⚠ 修好之后本测试会失败，那是预期的：届时请把断言反过来写。
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

    /// 一声词：读平（正确）反而比读成下滑（错误）分数差
    func testLevelToneScoringIsCurrentlyInverted() {
        let flat    = score([1, 1], syl2(start: 268, end: 264, wordDrop: 0))
        let falling = score([1, 1], syl2(start: 268, end: 264, wordDrop: 45))

        XCTAssertGreaterThan(flat, 0.5,
            "现状：读平（正确）不通关，DTW=\(flat)")
        XCTAssertLessThan(falling, 0.5,
            "现状：大幅下滑（错误）却通关，DTW=\(falling)")
        XCTAssertGreaterThan(flat, falling,
            "现状：正确发音分数劣于错误发音——评分方向是反的")
    }

    /// 音高绝对平稳 → SD=0 → normalize 返回全 0 → 拿到最差分
    func testPerfectlySteadyPitchGetsWorstScore() {
        let steady = score([1, 1], syl2(start: 265, end: 265, wordDrop: 0, jitter: 0))
        XCTAssertGreaterThan(steady, 5, "SD=0 退化为全 0 序列，DTW=\(steady)")
    }

    /// 对照：去声词方向正常，说明问题只出在低方差的平调
    func testFallingToneScoringIsCorrect() {
        let correct = score([4, 4], syl2(start: 285, end: 140, wordDrop: 0))
        let wrongFlat = score([4, 4], syl2(start: 265, end: 265, wordDrop: 0))
        XCTAssertLessThan(correct, 0.5, "4+4 正确急降应通关")
        XCTAssertGreaterThan(wrongFlat, 0.5, "4+4 错误平读应不通关")
    }
}
