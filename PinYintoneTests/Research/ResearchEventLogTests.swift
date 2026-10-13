import XCTest
@testable import PinYintone

@MainActor
final class ResearchEventLogTests: XCTestCase {

    private var log: ResearchEventLog { .shared }

    override func setUp() {
        super.setUp()
        ResearchTestSupport.freshAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 置为已纳入、采集中
    private func consent() {
        ResearchTestSupport.enrolledAccount()
    }

    // MARK: - 门禁在写入前

    func testNoEventsWithoutConsent() {
        XCTAssertFalse(log.log(.historyOpened), "未同意不得产生研究事件")
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testNoEventsWhenIneligible() {
        consent()
        ResearchStore.shared.update { $0.eligibility = "excluded:age" }
        XCTAssertFalse(log.log(.historyOpened))
        XCTAssertTrue(log.pending.isEmpty)
    }

    func testNoEventsOutsideWindow() {
        ResearchTestSupport.enrolledAccount(
            windowStart: Date().addingTimeInterval(-7200),
            windowEnd: Date().addingTimeInterval(-3600))
        XCTAssertFalse(log.log(.historyOpened))
        XCTAssertTrue(log.pending.isEmpty)
    }

    /// 事件里的界面语言是用户在 App 内选择的那一种，不是系统区域（R08）
    func testEventCarriesTheAppLanguage() {
        let before = LocalizationManager.shared.language
        defer { LocalizationManager.shared.setLanguage(before) }
        LocalizationManager.shared.setLanguage("ar")
        consent()
        XCTAssertTrue(log.log(.historyOpened))
        XCTAssertEqual(log.pending.last?.uiLanguage, "ar")
    }

    /// 队列落盘：App 被杀后事件不丢（此前只在内存里）
    func testPendingEventsSurviveRelaunch() {
        let key = ResearchTestSupport.enrolledAccount()
        XCTAssertTrue(log.log(.historyOpened))
        let id = log.pending[0].eventID
        ResearchStore.shared.activate(accountKey: nil)
        XCTAssertTrue(log.pending.isEmpty)
        ResearchStore.shared.activate(accountKey: key)
        XCTAssertEqual(log.pending.map(\.eventID), [id], "重启后应是同一条、同一个编号")
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
        ResearchEnrollment.withdraw()
        XCTAssertTrue(log.pending.isEmpty, "退出须立即清空待上传队列")
        XCTAssertFalse(log.log(.historyOpened), "退出后不得继续采集")
    }

    // MARK: - 命名转换

    func testFeedbackModeNamingConversion() {
        XCTAssertEqual(ResearchFeedbackMode(.staticColor).rawValue, "static_color")
        XCTAssertEqual(ResearchFeedbackMode(.dynamicF0).rawValue, "pitch_curve",
                       "字典用 pitch_curve，不是 App 内部的 dynamicF0")
    }
}

// MARK: - 补齐的埋点

@MainActor
final class RemainingEventWiringTests: XCTestCase {
    private var log: ResearchEventLog { .shared }

    override func setUp() {
        super.setUp()
        ResearchTestSupport.enrolledAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    func testFeedbackModeChangedCarriesBothModes() {
        let vm = ToneTrainingViewModel()
        vm.beginAttemptForTesting()          // 字典要求本事件必须挂在某次尝试上
        vm.logFeedbackModeChanged(from: .staticColor, to: .dynamicF0)
        let e = log.pending.last
        XCTAssertEqual(e?.name, .feedbackModeChanged)
        XCTAssertEqual(e?.payload["from_mode"], "static_color")
        XCTAssertEqual(e?.payload["to_mode"], "pitch_curve")
    }

    /// 已知缺口：录音前的切换按字典无法记录（attempt_id 必填）。
    /// 这条测试固化现状，若将来放宽字典须同步改写。
    func testModeChangeBeforeAnyAttemptIsNotLogged() {
        let vm = ToneTrainingViewModel()
        vm.logFeedbackModeChanged(from: .staticColor, to: .dynamicF0)
        XCTAssertTrue(log.pending.isEmpty,
                      "无 attempt 时不得发出违反字典的事件，也不得静默传 nil 绕过校验")
    }

    func testNoEventWhenModeDidNotActuallyChange() {
        let vm = ToneTrainingViewModel()
        vm.logFeedbackModeChanged(from: .dynamicF0, to: .dynamicF0)
        XCTAssertTrue(log.pending.isEmpty, "没真的切换就不该记一次切换")
    }

    func testCrashEventCarriesNoFabricatedTimestamp() {
        let n = ResearchCrashReporter.shared.record(crashCount: 2)
        XCTAssertEqual(n, 2)
        let crashes = log.pending.filter { $0.name == .crashReportReceived }
        XCTAssertEqual(crashes.count, 2)
        for c in crashes {
            XCTAssertTrue(c.payload.isEmpty,
                          "MXDiagnosticPayload 只有采集时间窗，无确切崩溃时刻——不得补造")
        }
    }

    func testZeroCrashesLogsNothing() {
        XCTAssertEqual(ResearchCrashReporter.shared.record(crashCount: 0), 0)
        XCTAssertTrue(log.pending.isEmpty)
    }

    /// 崩溃事件同样受研究门禁约束
    func testCrashEventGatedByConsent() {
        ResearchEnrollment.withdraw()
        XCTAssertEqual(ResearchCrashReporter.shared.record(crashCount: 3), 0,
                       "退出后不得再采集崩溃事件")
    }
}
