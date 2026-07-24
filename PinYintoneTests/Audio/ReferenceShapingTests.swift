import XCTest
@testable import PinYintone

/// TTS 参照整形（去下倾 + 重平滑 + 向理想轮廓混合）的行为验证。
///
/// 背景：AVSpeechSynthesizer 把词当句子读，叠加句子级下倾与句末降调。
/// 实测「医生」「参加」这类 1+1 全高平词的参照线一路下滑——学习者照着模仿
/// 会学错调，DTW 也拿这条错线打分。以下用合成的"劣质 TTS 曲线"量化验证矫正效果。
final class ReferenceShapingTests: XCTestCase {

    private let svc = SpeechService.shared

    /// 首末落差（Hz，正 = 下行）。
    /// 刻意**不**按标准差归一：归一化后的趋势对纯直线是尺度不变的
    /// （斜率再小、归一化趋势也不变），量不出"下倾被削平"这件事。
    private func dropHz(_ track: [Float]) -> Float {
        let v = track.filter { $0 > 0 }
        guard let first = v.first, let last = v.last else { return 0 }
        return first - last
    }

    /// 模拟 TTS：在本应高平的 1+1 词上叠加线性下倾
    private func decliningLevelTrack(count: Int = 48, drop: Float = 90) -> [Float] {
        (0..<count).map { 265 - drop * Float($0) / Float(count - 1) }
    }

    // MARK: - 去多余下倾

    func testDeclinationRemovedForLevelLevelWord() {
        let bad = decliningLevelTrack()              // 265 → 175，人为叠加 90 Hz 下倾
        let fixed = svc.removeExcessDeclination(bad, tones: [1, 1])

        XCTAssertEqual(dropHz(bad), 90, accuracy: 1, "构造的输入应有 90 Hz 下行")
        XCTAssertLessThan(dropHz(fixed), 20,
                          "1+1 全高平词的多余下倾应被基本消除")
    }

    /// 4+4 本来就该整体下行——不能被当作句调下倾抹掉
    func testGenuineFallingTrendIsPreserved() {
        let ideal44 = ToneContour.ideal(for: [4, 4])
        let fixed = svc.removeExcessDeclination(ideal44, tones: [4, 4])
        XCTAssertEqual(dropHz(fixed), dropHz(ideal44), accuracy: 5,
                       "4+4 的真实下行必须原样保留，不可被误伤")
    }

    // MARK: - 向理想轮廓混合

    func testBlendPullsShapeTowardIdeal() {
        let bad = decliningLevelTrack()
        let blended = svc.blendTowardIdeal(bad, tones: [1, 1], alpha: 0.55)
        XCTAssertLessThan(dropHz(blended), dropHz(bad) * 0.75,
                          "混合后应更接近 1+1 的水平形状")
    }

    func testBlendKeepsVoicedFramesVoiced() {
        var track = decliningLevelTrack()
        track[10] = 0; track[11] = 0          // 模拟无声段
        let blended = svc.blendTowardIdeal(track, tones: [1, 1])
        XCTAssertEqual(blended[10], 0, "无声帧必须保持 0（CLAUDE.md：不插值）")
        XCTAssertEqual(blended[11], 0)
        XCTAssertTrue(blended.filter { $0 > 0 }.allSatisfy { $0 > 0 },
                      "有声帧不得被压成 0")
    }

    func testBlendIsNoOpWithoutTones() {
        let track = decliningLevelTrack()
        XCTAssertEqual(svc.blendTowardIdeal(track, tones: []), track,
                       "缺少声调信息时不应改动（如真人录音路径）")
    }

    // MARK: - 重平滑

    func testSmoothingReducesJitter() {
        // 在平坦基线上叠加逐帧抖动
        let jittery: [Float] = (0..<40).map { 220 + ($0 % 2 == 0 ? 18 : -18) }
        let smoothed = svc.smoothReference(jittery)
        func roughness(_ xs: [Float]) -> Float {
            zip(xs, xs.dropFirst()).reduce(0) { $0 + abs($1.1 - $1.0) }
        }
        XCTAssertLessThan(roughness(smoothed), roughness(jittery) * 0.5,
                          "重平滑应显著降低帧间抖动")
    }

    // MARK: - 真实 TTS 集成验证

    /// 端到端跑真实 TTS：1+1 全高平词的参照线不应大幅下滑。
    /// 这是本次修复的原始病例——修复前「医生」「参加」的参照线一路下坠。
    func testRealTTSReferenceForLevelWordIsNotStronglyFalling() async throws {
        let track = await SpeechService.shared.synthesizeReferenceF0(for: "参加", tones: [1, 1])
        try XCTSkipIf(track.isEmpty, "该环境无可用中文 TTS 语音（或走向校验已回退），跳过")

        let voiced = track.filter { $0 != 0 }
        try XCTSkipIf(voiced.count < 12, "有声帧过少，跳过")

        // 返回值已 z-score 归一化，故单位为标准差
        let third = max(1, voiced.count / 3)
        let head = voiced.prefix(third).reduce(0, +) / Float(third)
        let tail = voiced.suffix(third).reduce(0, +) / Float(third)
        XCTAssertGreaterThan(tail - head, -1.2,
                             "1+1 全高平词的参照线不应大幅下滑（首末落差 \(tail - head) sd）")
    }

    func testSmoothingDoesNotCrossUnvoicedBoundary() {
        var track = [Float](repeating: 200, count: 10)
        track += [Float](repeating: 0, count: 4)      // 无声间隔
        track += [Float](repeating: 300, count: 10)
        let smoothed = svc.smoothReference(track)
        XCTAssertTrue(smoothed[10...13].allSatisfy { $0 == 0 }, "无声段保持 0")
        // 两侧不应因平滑而相互"渗透"
        XCTAssertEqual(smoothed[5], 200, accuracy: 1, "前段不应被后段拉高")
        XCTAssertEqual(smoothed[18], 300, accuracy: 1, "后段不应被前段拉低")
    }
}
