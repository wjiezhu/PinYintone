import XCTest
@testable import PinYintone

@MainActor
final class RewardLedgerTests: XCTestCase {

    private let ruleKey = "pt_research_reward_rule_version"

    override func setUp() {
        super.setUp()
        RewardLedger.shared.reset()
        RewardEventLog.shared.clearPendingOnWithdrawal()
        UserDefaults.standard.removeObject(forKey: ruleKey)
    }
    override func tearDown() {
        RewardLedger.shared.reset()
        UserDefaults.standard.removeObject(forKey: ruleKey)
        ResearchConsent.shared.withdraw()
        super.tearDown()
    }

    private func enableRule() { UserDefaults.standard.set("reward-1.0", forKey: ruleKey) }
    private func enableResearch() {
        ResearchEventLog.shared.eligibility = .eligible
        ResearchEventLog.shared.window = .init(start: Date().addingTimeInterval(-60),
                                               end: Date().addingTimeInterval(3600))
        ResearchConsent.shared.grant(textVersion: "c1", language: "zh")
    }

    /// 未配置规则版本 → 功能整体关闭，一分不发
    func testDisabledWhenNoRuleVersion() {
        XCTAssertFalse(RewardLedger.shared.isEnabled)
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: true), 0)
        XCTAssertEqual(RewardLedger.shared.total, 0)
    }

    /// 只有通过才发
    func testOnlyAwardsOnPass() {
        enableRule()
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: false), 0)
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: true), 1)
    }

    /// 每词首次通过才发——同词重练不再发，防止挑最容易的词刷分
    func testOnlyFirstPassPerLexeme() {
        enableRule()
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: true), 1)
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: true), 0)
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "bangzhu",
                                                  passed: true), 1)
        XCTAssertEqual(RewardLedger.shared.total, 2)
    }

    /// 同一次尝试重复结算不重复发奖（幂等键 = attemptID + 规则版本）
    func testIdempotentPerAttempt() {
        enableRule()
        let id = UUID()
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: id, lexemeID: "paobu",
                                                  passed: true), 1)
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: id, lexemeID: "paobu",
                                                  passed: true), 0)
        XCTAssertEqual(RewardLedger.shared.total, 1)
    }

    /// 未参加研究者照常拿业务积分，但**不生成研究镜像**（字典 §13）
    func testNonResearchUserGetsPointsButNoMirror() {
        enableRule()
        ResearchConsent.shared.withdraw()
        XCTAssertEqual(RewardLedger.shared.settle(attemptID: UUID(), lexemeID: "paobu",
                                                  passed: true), 1)
        XCTAssertTrue(RewardEventLog.shared.pending.isEmpty, "未参加研究不得生成镜像")
    }

    /// 已纳入者：镜像与业务发放共用同一 attemptID
    func testResearchMirrorSharesIdempotencyKey() {
        enableRule(); enableResearch()
        let id = UUID()
        RewardLedger.shared.settle(attemptID: id, lexemeID: "paobu", passed: true)
        let rec = RewardEventLog.shared.pending.first
        XCTAssertEqual(rec?.attemptID, id)
        XCTAssertEqual(rec?.rewardRuleVersion, "reward-1.0")
        XCTAssertEqual(rec?.pointsDelta, 1)
    }

    /// 字典 §13：**不因问卷完成、研究同意或答案倾向发分**。
    /// 结构性保证——发放入口只接受 attemptID/lexemeID/passed 三个参数，
    /// 完成问卷不经过任何发放路径。
    func testSurveyCompletionAwardsNothing() {
        enableRule(); enableResearch()
        let before = RewardLedger.shared.total
        ResearchSurveyTrigger.shared.markPostInvited()
        ResearchSurveyTrigger.shared.recordQualifyingAttempt(
            UUID(), taskType: .fixedWord, resultDisplayed: true)
        XCTAssertEqual(RewardLedger.shared.total, before, "问卷相关动作不得改变积分")
        XCTAssertTrue(RewardEventLog.shared.pending.isEmpty)
    }
}
