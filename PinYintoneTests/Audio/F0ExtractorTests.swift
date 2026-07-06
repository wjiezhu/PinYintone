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

    // MARK: - clean() 后处理

    func testCleanRemovesIsolatedSpikes() {
        // 孤立 1–2 帧的"有声"段（<24ms）是冲击噪声，应置 0
        var track = [Float](repeating: 0, count: 20)
        track[5] = 300                        // 单帧尖峰
        track[10] = 250; track[11] = 260      // 双帧尖峰
        let cleaned = extractor.clean(track)
        XCTAssertEqual(cleaned[5], 0, "单帧孤立尖峰应被清除")
        XCTAssertEqual(cleaned[10], 0, "双帧孤立尖峰应被清除")
        XCTAssertEqual(cleaned[11], 0, "双帧孤立尖峰应被清除")
    }

    func testCleanFixesOctaveDoubling() {
        // 稳定 200 Hz 序列中混入一帧 400 Hz（倍频错误）→ 应折回 ≈200
        var track = [Float](repeating: 200, count: 12)
        track[6] = 400
        let cleaned = extractor.clean(track)
        XCTAssertEqual(cleaned[6], 200, accuracy: 1, "倍频八度错误应折回")
    }

    func testCleanFixesOctaveHalving() {
        // 稳定 300 Hz 序列中混入一帧 150 Hz（半频错误）→ 应折回 ≈300
        var track = [Float](repeating: 300, count: 12)
        track[6] = 150
        let cleaned = extractor.clean(track)
        XCTAssertEqual(cleaned[6], 300, accuracy: 1, "半频八度错误应折回")
    }

    func testCleanKeepsUnvoicedZero() {
        // clean 不得给无声帧插值（CLAUDE.md）
        let track: [Float] = [200, 210, 220, 0, 0, 0, 230, 240, 250]
        let cleaned = extractor.clean(track)
        XCTAssertEqual(cleaned[3], 0)
        XCTAssertEqual(cleaned[4], 0)
        XCTAssertEqual(cleaned[5], 0)
    }

    func testCleanPreservesLegitimateToneMovement() {
        // 真实二声上升（160→248，逐帧 ≈6%）不应被八度纠错破坏
        let rise = (0..<20).map { 160 + Float($0) * 4.6 }
        let cleaned = extractor.clean(rise)
        for (orig, out) in zip(rise, cleaned) {
            XCTAssertEqual(out, orig, accuracy: 6, "平滑允许微调，但不得大改合法上升轨迹")
        }
    }
}
