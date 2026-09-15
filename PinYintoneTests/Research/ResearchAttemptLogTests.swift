import XCTest
@testable import PinYintone

@MainActor
final class ResearchAttemptLogTests: XCTestCase {

    private var log: ResearchAttemptLog { .shared }

    override func setUp() {
        super.setUp()
        log.clearPendingOnWithdrawal()
        ResearchEventLog.shared.eligibility = .eligible
        ResearchEventLog.shared.window = .init(start: Date().addingTimeInterval(-60),
                                               end: Date().addingTimeInterval(3600))
        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
    }
    override func tearDown() {
        log.clearPendingOnWithdrawal()
        ResearchConsent.shared.withdraw()
        super.tearDown()
    }

    private func begin(_ id: UUID = UUID()) -> UUID {
        log.begin(attemptID: id, taskType: .fixedWord,
                  lexemeVersionID: "lex-canjia", priorPracticeCount: nil)
        return id
    }

    // MARK: - 失败不得带分

    func testFailedAttemptKeepsMetricAndPassedNil() {
        let id = begin()
        log.markAnalyzing(id)
        log.markFailed(id, status: .analysisFailed, error: .noSignal)

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertNotNil(r)
        XCTAssertNil(r?.metricValue, "失败不得填零分替代——旧表的 -1 哨兵不要搬过来")
        XCTAssertNil(r?.passed, "无有效评分时 passed 为 nil，nil 不等于未通过")
        XCTAssertEqual(r?.errorCode, .noSignal)
        XCTAssertNotNil(r?.finishedAt)
    }

    func testSucceededAttemptCarriesMetric() {
        let id = begin()
        log.markAnalyzing(id)
        log.markSucceeded(id, metric: 0.21, passed: true)
        log.markResultDisplayed(id)

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertEqual(r?.metricValue, 0.21)
        XCTAssertEqual(r?.passed, true)
        XCTAssertNotNil(r?.resultDisplayedAt)
    }

    // MARK: - result_displayed_at 的语义

    func testResultDisplayedOnlySetWhenActuallyRendered() {
        let id = begin()
        log.markAnalyzing(id)
        log.markSucceeded(id, metric: 0.3, passed: true)
        log.finishWithoutDisplay(id)     // 裸测路径：算了分但不呈现

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertNotNil(r?.metricValue, "裸测照常算分入库")
        XCTAssertNil(r?.resultDisplayedAt,
                     "未呈现结果就不得填 resultDisplayedAt——后置问卷计数依赖它")
    }

    // MARK: - 门禁与时长

    func testNoAttemptRecordedWithoutConsent() {
        ResearchConsent.shared.withdraw()
        let id = begin()
        log.markFailed(id, status: .analysisFailed, error: .noSignal)
        XCTAssertTrue(log.pending.isEmpty, "未同意不得产生研究记录")
    }

    func testDurationsAreNonNegative() {
        let id = begin()
        log.markAnalyzing(id)
        log.markSucceeded(id, metric: 0.2, passed: true)
        log.markResultDisplayed(id)
        let r = log.pending.first { $0.attemptID == id }
        XCTAssertGreaterThanOrEqual(r?.recordingDurationMs ?? -1, 0)
        XCTAssertGreaterThanOrEqual(r?.analysisDurationMs ?? -1, 0)
    }

    func testWithdrawalClearsPendingAttempts() {
        let id = begin()
        log.markFailed(id, status: .analysisFailed, error: .noSignal)
        XCTAssertFalse(log.pending.isEmpty)
        log.clearPendingOnWithdrawal()
        XCTAssertTrue(log.pending.isEmpty)
    }

    /// 自测记录该词此前练过几次
    func testSelfTestCarriesPriorPracticeCount() {
        let id = UUID()
        log.begin(attemptID: id, taskType: .selfTest,
                  lexemeVersionID: "lex-canjia", priorPracticeCount: 7)
        log.markAnalyzing(id)
        log.markSucceeded(id, metric: 0.4, passed: true)
        log.finishWithoutDisplay(id)
        XCTAssertEqual(log.pending.first { $0.attemptID == id }?.priorPracticeCount, 7)
    }
}
