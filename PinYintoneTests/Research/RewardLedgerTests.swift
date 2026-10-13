import XCTest
@testable import PinYintone

@MainActor
final class RewardLedgerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        RewardLedger.shared.reset()
        RewardEventLog.shared.clearPendingOnWithdrawal()
        ResearchTestSupport.freshAccount()
        ResearchConfig.shared.setAvailableForTesting(nil)
    }
    override func tearDown() {
        RewardLedger.shared.reset()
        RewardEventLog.shared.clearPendingOnWithdrawal()
        ResearchTestSupport.tearDown()
        super.tearDown()
    }

    /// 积分由配置里的 reward_rule_version 开关。本轮正式配置不带它（功能关闭）。
    private func enableRule() {
        ResearchConfig.shared.setAvailableForTesting(
            .init(manifestID: "manifest-test", studyID: "study-test",
                  collectionStartAt: Date().addingTimeInterval(-3600),
                  collectionEndAt: Date().addingTimeInterval(86_400),
                  postTriggerCount: 5, consentVersion: ResearchConsent.textVersion,
                  rewardRuleVersion: "reward-1.0", isTest: true))
    }
    private func enableResearch() {
        ResearchTestSupport.enrolledAccount()
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
        SurveyCenter.recordQualifyingAttempt(
            UUID(), taskType: .fixedWord, resultDisplayed: true)
        SurveyCenter.invite(SurveyCenter.postKey)
        SurveyCenter.submit(SurveyCenter.postKey, answers: [
            SurveyAnswer(questionID: "POST01", state: .answered, optionCodes: ["agree"],
                         textValue: nil, answeredAt: Date())])
        XCTAssertEqual(RewardLedger.shared.total, before, "问卷相关动作不得改变积分")
        XCTAssertTrue(RewardEventLog.shared.pending.isEmpty)
    }
}
