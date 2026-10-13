import XCTest
@testable import PinYintone

/// 自由文本（关卡 3）的研究记录约束。
@MainActor
final class FreeTextAttemptTests: XCTestCase {

    private var log: ResearchAttemptLog { .shared }

    override func setUp() {
        super.setUp()
        ResearchTestSupport.enrolledAccount()
    }
    override func tearDown() {
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 自由文本**不带词条编号**，也就不可能夹带用户原文（字典 §7）
    func testFreeTextCarriesNoLexemeID() {
        let id = UUID()
        log.begin(attemptID: id, taskType: .freeText,
                  lexemeVersionID: nil, priorPracticeCount: nil)
        log.markAnalyzing(id)
        log.markSucceeded(id, metric: 0.3, passed: true)
        log.markResultDisplayed(id)

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertEqual(r?.taskType, .freeText)
        XCTAssertNil(r?.lexemeVersionID, "free_text 不得带词条编号")
    }

    /// 自由文本即便结果已显示，也不计入使用后问卷的 5 次阈值
    func testFreeTextNeverCountsTowardPostSurvey() {
        for _ in 0..<10 {
            SurveyCenter.recordQualifyingAttempt(
                UUID(), taskType: .freeText, resultDisplayed: true)
        }
        XCTAssertEqual(SurveyCenter.qualifyingCount, 0,
                       "自由文本不计入这 5 次")
    }

    /// 没录上时不生成发音成绩（禁令 9），新表保持 nil 而非零分
    func testFreeTextFailureKeepsNoScore() {
        let id = UUID()
        log.begin(attemptID: id, taskType: .freeText,
                  lexemeVersionID: nil, priorPracticeCount: nil)
        log.markAnalyzing(id)
        log.markFailed(id, status: .analysisFailed, error: .noSignal)

        let r = log.pending.first { $0.attemptID == id }
        XCTAssertNil(r?.metricValue)
        XCTAssertNil(r?.passed)
        XCTAssertEqual(r?.errorCode, .noSignal)
    }
}
