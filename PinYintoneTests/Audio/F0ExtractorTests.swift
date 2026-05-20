import XCTest
@testable import PinYintone

final class F0ExtractorTests: XCTestCase {
    var extractor: F0Extractor!

    override func setUp() {
        super.setUp()
        extractor = F0Extractor()
    }

    override func tearDown() {
        extractor = nil
        super.tearDown()
    }

    /// 生成正弦波帧
    private func sineFrame(freq: Float, count: Int = 512, sampleRate: Float = 16_000) -> [Float] {
        (0..<count).map { sinf(2 * .pi * freq * Float($0) / sampleRate) }
    }

    func testSineWave440Hz() {
        let f0 = extractor.extract(frame: sineFrame(freq: 440))
        XCTAssertEqual(f0, 440, accuracy: 10, "440 Hz 正弦波应被检测为 ≈440 Hz")
    }

    func testSineWave200Hz() {
        let f0 = extractor.extract(frame: sineFrame(freq: 200))
        XCTAssertEqual(f0, 200, accuracy: 8, "200 Hz（普通话常见基频）应被准确检测")
    }

    func testSilenceReturnsZero() {
        let frame = [Float](repeating: 0, count: 512)
        XCTAssertEqual(extractor.extract(frame: frame), 0, "全零帧应返回 0")
    }

    func testF0BelowDetectionRangeReturnsZero() {
        // 50 Hz 低于 75 Hz 下限（周期 320 > maxTau 213），应无法检测
        let f0 = extractor.extract(frame: sineFrame(freq: 50))
        XCTAssertEqual(f0, 0, "低于检测下限的频率应返回 0")
    }

    func testNormalizeZScoreProperties() {
        let track: [Float] = [100, 110, 120, 130, 140, 150]
        let norm = extractor.normalize(track)

        let mean = norm.reduce(0, +) / Float(norm.count)
        let variance = norm.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(norm.count)
        XCTAssertEqual(mean, 0, accuracy: 1e-4, "z-score 后均值应 ≈ 0")
        XCTAssertEqual(sqrt(variance), 1, accuracy: 1e-4, "z-score 后标准差应 ≈ 1")
    }

    func testNormalizeKeepsUnvoicedFramesZero() {
        // 0 值（无声帧）归一化后仍应为 0（CLAUDE.md）
        let track: [Float] = [0, 120, 0, 130, 140]
        let norm = extractor.normalize(track)
        XCTAssertEqual(norm[0], 0, "无声帧应保持 0")
        XCTAssertEqual(norm[2], 0, "无声帧应保持 0")
    }

    func testNormalizeEmptyOrSingleVoiced() {
        XCTAssertEqual(extractor.normalize([]), [])
        // 仅一个有声帧时无法求标准差 → 全 0
        XCTAssertEqual(extractor.normalize([0, 100, 0]), [0, 0, 0])
    }
}
