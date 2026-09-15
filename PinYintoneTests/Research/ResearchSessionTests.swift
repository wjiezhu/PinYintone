import XCTest
@testable import PinYintone

@MainActor
final class ResearchSessionTests: XCTestCase {

    func testBackgroundUnderThresholdKeepsSession() {
        let s = ResearchSession.shared
        s.rotate(now: 1000)
        let before = s.sessionID
        s.didEnterBackground(now: 1000)
        XCTAssertFalse(s.willEnterForeground(now: 1000 + 29 * 60))
        XCTAssertEqual(s.sessionID, before, "后台不足 30 分钟不轮换")
    }

    func testBackgroundOverThresholdRotatesSession() {
        let s = ResearchSession.shared
        s.rotate(now: 2000)
        let before = s.sessionID
        s.didEnterBackground(now: 2000)
        XCTAssertTrue(s.willEnterForeground(now: 2000 + 31 * 60))
        XCTAssertNotEqual(s.sessionID, before, "后台超过 30 分钟须新会话")
    }

    func testForegroundWithoutBackgroundDoesNotRotate() {
        let s = ResearchSession.shared
        s.rotate(now: 3000)
        let before = s.sessionID
        XCTAssertFalse(s.willEnterForeground(now: 3000 + 99 * 60))
        XCTAssertEqual(s.sessionID, before)
    }

    func testElapsedIsNonNegative() {
        let s = ResearchSession.shared
        s.rotate()
        XCTAssertGreaterThanOrEqual(s.elapsedMs, 0, "字典要求非负且单调")
    }
}
