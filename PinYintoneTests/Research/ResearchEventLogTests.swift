import XCTest
@testable import PinYintone

@MainActor
final class ResearchEventLogTests: XCTestCase {

    private var log: ResearchEventLog { .shared }

    override func setUp() {
        super.setUp()
        log.clearPendingOnWithdrawal()
        ResearchConsent.shared.withdraw()
        log.eligibility = .eligible
        log.window = .init(start: Date().addingTimeInterval(-60),
                           end: Date().addingTimeInterval(3600))
    }
    override func tearDown() {
        log.clearPendingOnWithdrawal()
        ResearchConsent.shared.withdraw()
        super.tearDown()
    }

    private func consent() {
        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
    }

    // MARK: - 门禁在写入前

    func testNoEventsWithoutConsent() {
        XCTAssertFalse(log.log(.historyOpened), "未同意不得产生研究事件")
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testNoEventsWhenIneligible() {
        consent()
        log.eligibility = .excluded(.age)
        XCTAssertFalse(log.log(.historyOpened))
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testNoEventsOutsideWindow() {
        consent()
        log.window = .init(start: Date().addingTimeInterval(-7200),
                           end: Date().addingTimeInterval(-3600))
        XCTAssertFalse(log.log(.historyOpened))
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testLogsWhenAllConditionsMet() {
        consent()
        XCTAssertTrue(log.log(.historyOpened))
        XCTAssertEqual(log.pending.count, 1)
        XCTAssertEqual(log.pending.first?.name, .historyOpened)
    }

    // MARK: - 校验

    func testAttemptRequiredEventsRejectedWithoutAttemptID() {
        consent()
        for name in ResearchEventName.allCases where name.requiresAttempt {
            XCTAssertFalse(log.log(name), "\(name.rawValue) 缺 attempt_id 应被拒绝")
        }
        XCTAssertTrue(log.pending.isEmpty, "校验失败的事件不得入队")
    }

    func testPayloadKeyWhitelistEnforced() {
        consent()
        XCTAssertFalse(log.log(.historyOpened, payload: ["foo": "bar"]),
                       "白名单外的 payload 字段应被拒绝")
        XCTAssertFalse(log.log(.taskOpened, payload: ["mode": "static_color"]),
                       "字段属于别的事件也不行")
        XCTAssertTrue(log.log(.taskOpened, payload: ["task_type": "fixed_word"]))
    }

    // MARK: - 幂等与撤回

    func testEachEventGetsUniqueIdempotencyKey() {
        consent()
        for _ in 0..<5 { log.log(.historyOpened) }
        XCTAssertEqual(Set(log.pending.map(\.eventID)).count, 5)
    }

    func testWithdrawalClearsPendingQueue() {
        consent()
        log.log(.historyOpened)
        XCTAssertFalse(log.pending.isEmpty)
        ResearchConsent.shared.withdraw()
        log.clearPendingOnWithdrawal()
        XCTAssertTrue(log.pending.isEmpty, "撤回须立即清空待上传队列")
        XCTAssertFalse(log.log(.historyOpened), "撤回后不得继续采集")
    }

    // MARK: - 命名转换

    func testFeedbackModeNamingConversion() {
        XCTAssertEqual(ResearchFeedbackMode(.staticColor).rawValue, "static_color")
        XCTAssertEqual(ResearchFeedbackMode(.dynamicF0).rawValue, "pitch_curve",
                       "字典用 pitch_curve，不是 App 内部的 dynamicF0")
    }
}
