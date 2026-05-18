import XCTest
@testable import Pinyintone

final class DTWAnalyzerTests: XCTestCase {
    var analyzer: DTWAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = DTWAnalyzer()
    }

    func testIdenticalSequencesDistanceIsZero() {
        // 相同序列 DTW 距离应为 0
        fatalError("TODO: 实现")
    }

    func testPassThresholdBoundary() {
        // dtwScore=0.50 应为 .needsPractice（不通关边界）
        // dtwScore=0.49 应通关（.needsPractice 但 passed）
        fatalError("TODO: 实现")
    }

    func testTimeShiftedSequenceLowerDistanceThanRandom() {
        // 时移相似序列的 DTW 距离 < 随机序列
        fatalError("TODO: 实现")
    }

    func testGradeMappingBoundaries() {
        // 验证 excellent(≤0.2) / good(0.2–0.35) / needsPractice(0.35–0.5) / fail(>0.5)
        fatalError("TODO: 实现")
    }
}
