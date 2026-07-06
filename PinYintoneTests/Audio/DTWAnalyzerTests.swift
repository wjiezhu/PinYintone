import XCTest
@testable import PinYintone

final class DTWAnalyzerTests: XCTestCase {
    var analyzer: DTWAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = DTWAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    func testIdenticalSequencesDistanceIsZero() {
        let s: [Float] = [1, 2, 3, 4, 5]
        XCTAssertEqual(analyzer.distance(reference: s, candidate: s), 0, accuracy: 1e-6,
                       "相同序列的归一化 DTW 距离应为 0")
    }

    func testEmptyAfterZeroFilteringReturnsMaxScore() {
        // 全 0（无声）序列在过滤后为空 → 无法比较，返回有限哨兵值
        // （不能用 .infinity：JSONEncoder 编码 infinity 会抛错，导致记录无法上报）
        XCTAssertEqual(analyzer.distance(reference: [0, 0], candidate: [1, 2]),
                       DTWAnalyzer.maxScore)
    }

    func testTimeShiftedSequenceLowerDistanceThanDissimilar() {
        // +2 偏置避免 0 被过滤
        let target = (0..<20).map { sinf(Float($0) * 0.5) + 2 }
        let shifted = (0..<20).map { sinf((Float($0) + 1) * 0.5) + 2 }   // 相位平移，形状相似
        let dissimilar = [Float](repeating: 5, count: 20)                // 平直，形状迥异

        let dShift = analyzer.distance(reference: target, candidate: shifted)
        let dDiff = analyzer.distance(reference: target, candidate: dissimilar)
        XCTAssertLessThan(dShift, dDiff, "时移相似序列的 DTW 距离应小于形状迥异序列")
    }

    func testGradeMappingBoundaries() {
        XCTAssertEqual(analyzer.grade(dtwScore: 0.10), .excellent)
        XCTAssertEqual(analyzer.grade(dtwScore: 0.20), .good)          // 0.2 不属于 <0.2
        XCTAssertEqual(analyzer.grade(dtwScore: 0.34), .good)
        XCTAssertEqual(analyzer.grade(dtwScore: 0.35), .needsPractice)
        XCTAssertEqual(analyzer.grade(dtwScore: 0.50), .needsPractice) // 0.5 含在通关内
        XCTAssertEqual(analyzer.grade(dtwScore: 0.51), .fail)
    }

    func testPassThresholdBoundary() {
        XCTAssertTrue(analyzer.passed(0.50), "0.5 应通关（CLAUDE.md：≤0.5）")
        XCTAssertTrue(analyzer.passed(0.49))
        XCTAssertFalse(analyzer.passed(0.51), ">0.5 不通关")
    }
}
