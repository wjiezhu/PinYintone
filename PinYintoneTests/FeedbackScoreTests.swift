import XCTest
@testable import PinYintone

final class FeedbackScoreTests: XCTestCase {

    private func score(_ dtw: Float) -> Int {
        FeedbackResult(dtwScore: dtw, grade: .good, attemptNumber: 1, segments: []).score
    }

    func testPerfectAndWorst() {
        XCTAssertEqual(score(0.0), 100, "DTW 0 → 满分")
        XCTAssertEqual(score(1.0), 0, "DTW 1.0 → 0 分")
        XCTAssertEqual(score(2.0), 0, "超出仍夹到 0")
    }

    func testGradeBoundaries() {
        XCTAssertEqual(score(0.2), 90, "优秀下界")
        XCTAssertEqual(score(0.35), 75, "良好下界")
        XCTAssertEqual(score(0.5), 60, "通关线 = 60 分")
    }

    func testPassLineIsSixty() {
        // ≤0.5 通关 → ≥60 分；>0.5 不通关 → <60 分
        XCTAssertGreaterThanOrEqual(score(0.49), 60)
        XCTAssertLessThan(score(0.51), 60)
    }

    func testMonotonicDecreasing() {
        // DTW 越大，分数越低（单调）
        var last = 101
        for i in 0...20 {
            let s = score(Float(i) / 20.0)
            XCTAssertLessThanOrEqual(s, last)
            XCTAssertTrue((0...100).contains(s))
            last = s
        }
    }
}
