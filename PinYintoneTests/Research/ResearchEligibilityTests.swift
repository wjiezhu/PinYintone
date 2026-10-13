import XCTest
@testable import PinYintone

/// 端侧资格门禁。字典 §1 要求「仅符合条件并明确同意者写入研究库」，
/// 且禁止后台先全量收集再于导出时过滤——所以这里判错就是数据污染。
final class ResearchEligibilityTests: XCTestCase {

    private func evaluate(adult: Bool? = true,
                          nations: Set<String>? = ["MA"],
                          stage: String? = "hsk2",
                          consent: Bool = true) -> ResearchEligibility.Outcome {
        ResearchEligibility.evaluate(isAdult: adult, nationalities: nations,
                                     courseStage: stage, consentGranted: consent)
    }

    func testTypicalTargetParticipantIsEligible() {
        XCTAssertEqual(evaluate(), .eligible)
    }

    // MARK: - 排除条件

    func testMinorExcluded() {
        XCTAssertEqual(evaluate(adult: false), .excluded(.age))
    }

    func testNonMoroccanExcluded() {
        XCTAssertEqual(evaluate(nations: ["FR"]), .excluded(.nationality))
    }

    func testMultipleNationalitiesIncludingMoroccoIsEligible() {
        // B02 允许多选；含 MA 即符合国籍条件
        XCTAssertEqual(evaluate(nations: ["FR", "MA"]), .eligible)
    }

    func testCourseStageWhitelistFollowsResearchDocs() {
        // 以三份研究文档的 eligibility_spec 为准：hsk1/2/3 全部纳入
        for s in ["hsk1", "hsk2", "hsk3"] {
            XCTAssertEqual(evaluate(stage: s), .eligible, "\(s) 应纳入")
        }
        for s in ["hsk4_plus", "other", "unsure"] {
            XCTAssertEqual(evaluate(stage: s), .excluded(.courseStage), "\(s) 不应纳入")
        }
    }

    /// 本轮**不区分新旧用户**（需求 R01、验收 A03/A04）：纳入判定里根本没有
    /// 使用史这个输入——旧用户、新用户、识别不了的，走同一个口径。
    func testPriorUseIsNotAnInputToEligibility() {
        XCTAssertEqual(evaluate(), .eligible)
        XCTAssertEqual(ResearchEligibility.version, "eligibility-2.0",
                       "规则变了版本号必须跟着变")
    }

    /// 识别不了使用史时如实是 unknown / insufficient，不为了通过检查写成 new
    func testUnknownPriorUseStaysUnknown() {
        XCTAssertEqual(PriorUse.unknown.status, .unknown)
        XCTAssertEqual(PriorUse.unknown.evidence, .insufficient)
    }

    // MARK: - 缺失不等于不合格，也不等于合格

    func testMissingBackgroundIsPendingNotExcluded() {
        XCTAssertEqual(evaluate(adult: nil), .pending)
        XCTAssertEqual(evaluate(nations: nil), .pending)
        XCTAssertEqual(evaluate(stage: nil), .pending)
    }

    func testPreferNotToAnswerNationalityIsNotEligible() {
        // prefer_not 视为空集：没有 MA 证据，不得推定满足
        XCTAssertEqual(evaluate(nations: []), .excluded(.nationality))
    }

    // MARK: - 同意是前提

    func testWithoutConsentNeverEligible() {
        // 即便背景全部符合，未同意也不产生参与者（字典 §5）
        XCTAssertEqual(evaluate(consent: false), .pending)
    }

    // MARK: - 新旧用户证据

    func testLegacyAppleIDProvesReturning() {
        let hit = PriorUse.fromLegacyLookup(foundInLegacy: true)
        XCTAssertEqual(hit.status, .returning)
        XCTAssertEqual(hit.evidence, .verifiedAccountHistory,
                       "旧版强制 Apple 登录且无游客路径，命中即可确证")
    }

    func testAbsenceFromLegacyIsWeakEvidence() {
        let miss = PriorUse.fromLegacyLookup(foundInLegacy: false)
        XCTAssertEqual(miss.status, .new)
        XCTAssertEqual(miss.evidence, .insufficient,
                       "查不到只说明无证据，不得声称已核实为新用户")
    }

    // MARK: - 持久化编码

    func testOutcomeStorageRoundTrips() {
        for outcome in [ResearchEligibility.Outcome.eligible, .pending,
                        .excluded(.age), .excluded(.nationality), .excluded(.courseStage)] {
            var state = ResearchState()
            state.eligibility = outcome.storageValue
            XCTAssertEqual(state.eligibilityOutcome, outcome)
        }
        XCTAssertEqual(ResearchState().eligibilityOutcome, .pending, "没判过就是 pending")
    }
}
