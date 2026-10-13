import XCTest
@testable import PinYintone

/// 研究门禁（需求 R04 / R08）。两道门：能不能产生新数据、能不能补传旧数据。
@MainActor
final class ResearchGateTests: XCTestCase {

    private let now = Date()

    private func enrolled(start: TimeInterval = -3600, end: TimeInterval = 3600) -> ResearchState {
        var s = ResearchState()
        s.participation = .enrolled
        s.eligibility = "eligible"
        s.participantID = "p"
        s.manifestID = "m"
        s.windowStart = now.addingTimeInterval(start)
        s.windowEnd = now.addingTimeInterval(end)
        return s
    }

    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 左闭右开：起点纳入、终点排除（验收 A22）
    func testWindowIsHalfOpen() {
        let start = now, end = now.addingTimeInterval(5 * 86_400)
        let window = ResearchGate.CollectionWindow(start: start, end: end)
        XCTAssertTrue(window.contains(start), "起点应纳入")
        XCTAssertTrue(window.contains(end.addingTimeInterval(-0.001)))
        XCTAssertFalse(window.contains(end), "终点应排除")
        XCTAssertFalse(window.contains(start.addingTimeInterval(-0.001)))
    }

    func testCollectsOnlyWhenEnrolledEligibleIdentifiedAndInsideWindow() {
        XCTAssertTrue(ResearchGate.shouldCollect(state: enrolled(), now: now))

        var noWindow = enrolled()
        noWindow.windowStart = nil
        XCTAssertFalse(ResearchGate.shouldCollect(state: noWindow, now: now),
                       "窗口未知不采集，不猜测")

        var noIdentity = enrolled()
        noIdentity.participantID = nil
        XCTAssertFalse(ResearchGate.shouldCollect(state: noIdentity, now: now))

        var excluded = enrolled()
        excluded.eligibility = "excluded:age"
        XCTAssertFalse(ResearchGate.shouldCollect(state: excluded, now: now))

        XCTAssertFalse(ResearchGate.shouldCollect(state: enrolled(start: -7200, end: -3600), now: now),
                       "窗口已关闭，不再产生新研究数据")
        XCTAssertFalse(ResearchGate.shouldCollect(state: enrolled(start: 60, end: 3600), now: now),
                       "窗口未开始")
    }

    /// 本地同意不等于已参加：服务端确认纳入之前不产生研究日志（R02）
    func testConsentAloneDoesNotCollect() {
        for participation in [ResearchState.Participation.notAsked, .declined,
                              .consentedPending, .ineligible, .withdrawn] {
            var s = enrolled()
            s.participation = participation
            XCTAssertFalse(ResearchGate.shouldCollect(state: s, now: now), "\(participation)")
        }
    }

    /// 窗口关闭后：不能产生新数据，但窗口内合法产生的待传数据仍可补传（R04）
    func testUploadStillAllowedAfterWindowCloses() {
        let closed = enrolled(start: -7200, end: -3600)
        XCTAssertFalse(ResearchGate.shouldCollect(state: closed, now: now))
        XCTAssertTrue(ResearchGate.canUpload(state: closed))
    }

    /// 退出后既不采集也不补传；有待同步的退出指令时也不补传
    func testNoUploadAfterWithdrawal() {
        var s = enrolled()
        s.pendingWithdrawal = .init(participantID: "p", consentVersion: "c",
                                    language: "fr", occurredAt: now)
        XCTAssertFalse(ResearchGate.canUpload(state: s))
        s.participation = .withdrawn
        XCTAssertFalse(ResearchGate.canUpload(state: s))
        XCTAssertFalse(ResearchGate.shouldCollect(state: s, now: now))
    }

    /// 窗口关闭不清掉合法的待传记录
    func testWindowClosingKeepsPendingQueue() {
        ResearchTestSupport.enrolledAccount()
        XCTAssertTrue(ResearchEventLog.shared.log(.historyOpened))
        ResearchStore.shared.update { s in
            s.windowEnd = Date().addingTimeInterval(-10)       // 窗口刚关
        }
        XCTAssertFalse(ResearchEventLog.shared.log(.historyOpened), "窗口外不再入队")
        XCTAssertEqual(ResearchEventLog.shared.pending.count, 1, "窗口内的那条还在等补传")
        XCTAssertTrue(ResearchGate.canUpload(state: ResearchStore.shared.state))
    }
}
