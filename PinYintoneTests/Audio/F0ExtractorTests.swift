import XCTest
@testable import Pinyintone

final class F0ExtractorTests: XCTestCase {
    var extractor: F0Extractor!

    override func setUp() {
        super.setUp()
        extractor = F0Extractor()
    }

    func testSineWave440Hz() {
        // 生成 440 Hz 正弦波（512 samples @16kHz），断言 extract() ≈ 440 ± 5 Hz
        fatalError("TODO: 实现")
    }

    func testSilenceReturnsZero() {
        // 全零帧（512 samples），断言 extract() == 0.0
        fatalError("TODO: 实现")
    }

    func testNormalizeZScoreProperties() {
        // 给定非零 F0 序列，断言 normalize() 输出均值 ≈ 0，标准差 ≈ 1
        fatalError("TODO: 实现")
    }

    func testF0OutsideDetectionRangeReturnsZero() {
        // 50 Hz 正弦波（低于 75 Hz 下限），断言结果 == 0.0
        fatalError("TODO: 实现")
    }
}
