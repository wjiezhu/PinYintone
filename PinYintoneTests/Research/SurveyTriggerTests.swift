import XCTest
@testable import PinYintone

/// 问卷触发口径（字典 §3 / §15 验收场景）。四条规则各有一条测试守着。
@MainActor
final class SurveyTriggerTests: XCTestCase {

    private var trigger: ResearchSurveyTrigger { .shared }

    override func setUp() {
        super.setUp()
        trigger.reset()
        trigger.configure(threshold: 5)
    }
    override func tearDown() { trigger.reset(); super.tearDown() }

    /// 第 5 次达到阈值时邀请，且只邀请一次
    func testInvitesOnceAtThreshold() {
        var invitations = 0
        for _ in 0..<8 {
            if trigger.recordQualifyingAttempt(UUID(), taskType: .fixedWord,
                                               resultDisplayed: true) {
                invitations += 1
                trigger.markPostInvited()
            }
        }
        XCTAssertEqual(invitations, 1, "达到阈值只邀请一次")
        XCTAssertEqual(trigger.qualifyingCount, 8, "超过阈值后仍继续计数")
    }

    /// 验收场景：第 5 次分析成功但**结果未显示**不弹问卷
    func testResultNotDisplayedDoesNotCount() {
        for _ in 0..<5 {
            XCTAssertFalse(trigger.recordQualifyingAttempt(
                UUID(), taskType: .fixedWord, resultDisplayed: false))
        }
        XCTAssertEqual(trigger.qualifyingCount, 0, "结果没显示就不算一次合格练习")
    }

    /// 自由文本不计入这 5 次
    func testFreeTextDoesNotCount() {
        for _ in 0..<5 {
            trigger.recordQualifyingAttempt(UUID(), taskType: .freeText,
                                            resultDisplayed: true)
        }
        XCTAssertEqual(trigger.qualifyingCount, 0)
    }

    /// 裸测自测也不计入
    func testSelfTestDoesNotCount() {
        trigger.recordQualifyingAttempt(UUID(), taskType: .selfTest, resultDisplayed: true)
        XCTAssertEqual(trigger.qualifyingCount, 0)
    }

    /// 同一次练习的结果重复渲染不得重复计次
    func testSameAttemptCountedOnce() {
        let id = UUID()
        for _ in 0..<4 {
            trigger.recordQualifyingAttempt(id, taskType: .fixedWord, resultDisplayed: true)
        }
        XCTAssertEqual(trigger.qualifyingCount, 1, "同一 attempt 只计一次")
    }

    /// 同词重录可累计，不要求 5 个不同词
    func testRepeatedPracticeOfSameWordAccumulates() {
        var reached = false
        for _ in 0..<5 {
            // 不同 attemptID、同一个词
            if trigger.recordQualifyingAttempt(UUID(), taskType: .fixedWord,
                                               resultDisplayed: true) { reached = true }
        }
        XCTAssertTrue(reached, "同词重录应能累计到阈值")
    }

    // MARK: - 前置问卷时间定位

    func testPreTimingBeforeFirstAttempt() {
        XCTAssertTrue(trigger.shouldInvitePre)
        XCTAssertEqual(trigger.preTimingClass, "before_first_attempt")
    }

    func testPreBecomesLateAfterPracticeStarted() {
        trigger.markFirstAttemptStarted()
        XCTAssertEqual(trigger.preTimingClass, "late_pre",
                       "开始练习后提交的前置问卷不能算作练习前调查")
        XCTAssertFalse(trigger.shouldInvitePre, "错过时点就不再作为前置问卷邀请")
    }

    func testResetClearsEverything() {
        trigger.recordQualifyingAttempt(UUID(), taskType: .fixedWord, resultDisplayed: true)
        trigger.markPostInvited()
        trigger.markFirstAttemptStarted()
        trigger.reset()
        XCTAssertEqual(trigger.qualifyingCount, 0)
        XCTAssertFalse(trigger.hasInvitedPost)
        XCTAssertFalse(trigger.hasStartedAnyAttempt)
    }
}
