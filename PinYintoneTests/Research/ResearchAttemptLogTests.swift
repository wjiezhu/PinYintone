import XCTest
@testable import PinYintone

@MainActor
final class ResearchAttemptLogTests: XCTestCase {

    private var log: ResearchAttemptLog { .shared }

    override func setUp() {
        super.setUp()
        ResearchTestSupport.enrolledAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
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
        ResearchTestSupport.freshAccount()       // 未参加研究
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

    // MARK: - 四种结局分别保存（需求 R07、验收 A14 / A18）

    /// 取消不是失败：没有成绩，也不强求错误码
    func testCancelledAttemptHasNoScoreAndNoError() {
        let id = begin()
        log.markCancelled(id)
        let r = log.pending.first { $0.attemptID == id }
        XCTAssertEqual(r?.status, .cancelled)
        XCTAssertNil(r?.metricValue)
        XCTAssertNil(r?.passed)
        XCTAssertNil(r?.errorCode)
        XCTAssertNotNil(r?.finishedAt)
    }

    /// 被系统打断：确知没完成、不确知原因 → 未知中断
    func testInterruptedAttemptIsRecordedAsUnknownInterruption() {
        let id = begin()
        log.markInterrupted(id)
        let r = log.pending.first { $0.attemptID == id }
        XCTAssertEqual(r?.status, .interruptedUnknown)
        XCTAssertNil(r?.metricValue)
        XCTAssertNil(r?.passed)
    }

    /// 录音途中 App 被杀：下次启动时这条尝试按未知中断结账，而不是消失，
    /// 也不被编成崩溃或失败。
    func testAttemptLeftInFlightBecomesUnknownInterruptionAfterRelaunch() {
        let key = ResearchStore.shared.accountKey
        let id = begin()
        log.markAnalyzing(id)
        XCTAssertTrue(log.pending.isEmpty, "还在进行中，不应已入待传队列")

        ResearchStore.shared.activate(accountKey: nil)      // 进程结束
        ResearchStore.shared.activate(accountKey: key)      // 再次启动

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertEqual(r?.status, .interruptedUnknown)
        XCTAssertNil(r?.metricValue)
        XCTAssertNil(r?.finishedAt, "结束时间不知道就留空，不补造")
        XCTAssertEqual(r?.timeQuality, .unknown)
        XCTAssertFalse(log.isTracking(id))
    }

    /// NaN / Infinity / 负数不是成绩：按分析失败记，不带分
    func testNonFiniteMetricIsRecordedAsFailureNotScore() {
        for bad in [Double.nan, .infinity, -1] {
            let id = begin()
            log.markAnalyzing(id)
            log.markSucceeded(id, metric: bad, passed: true)
            let r = log.pending.first { $0.attemptID == id }
            XCTAssertEqual(r?.status, .analysisFailed, "\(bad)")
            XCTAssertNil(r?.metricValue)
            XCTAssertNil(r?.passed)
            XCTAssertEqual(r?.errorCode, .analysisEngineError)
        }
    }

    /// 重录是新尝试、新编号，并关联上一次
    func testRetryGetsNewIDAndLinksToPrevious() {
        let first = begin()
        log.markCancelled(first)
        let second = UUID()
        log.begin(attemptID: second, taskType: .fixedWord, lexemeVersionID: "lex-canjia",
                  priorPracticeCount: nil, retryOf: first)
        log.markCancelled(second)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(log.pending.first { $0.attemptID == second }?.retryOfAttemptID, first)
        XCTAssertNil(log.pending.first { $0.attemptID == first }?.retryOfAttemptID)
    }

    /// 待传队列落盘
    func testPendingAttemptsSurviveRelaunch() {
        let key = ResearchStore.shared.accountKey
        let id = begin()
        log.markFailed(id, status: .analysisFailed, error: .noSignal)
        ResearchStore.shared.activate(accountKey: nil)
        ResearchStore.shared.activate(accountKey: key)
        XCTAssertEqual(log.pending.map(\.attemptID), [id])
    }
}
