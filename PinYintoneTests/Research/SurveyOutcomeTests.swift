import XCTest
@testable import PinYintone

/// 背景表 → 端侧资格判定的派生逻辑（字典 §10）。
final class SurveyOutcomeTests: XCTestCase {

    private func outcome(_ pairs: [(String, [String]?, SurveyAnswer.State)]) -> SurveyOutcome {
        SurveyOutcome(formKey: "background_v1", formVersion: "v1",
                      translationVersion: "i18n", language: "zh",
                      answers: pairs.map {
                          SurveyAnswer(questionID: $0.0, state: $0.2,
                                       optionCodes: $0.1, textValue: nil,
                                       answeredAt: Date())
                      },
                      status: "complete", startedAt: nil, submittedAt: Date())
    }

    func testAdultAndNationalityDerived() {
        let o = outcome([("B01", ["adult"], .answered),
                         ("B02", ["MA", "FR"], .answered),
                         ("B03", ["hsk2"], .answered)])
        XCTAssertEqual(o.isAdult, true)
        XCTAssertEqual(o.nationalities, ["MA", "FR"])
        XCTAssertEqual(o.courseStage, "hsk2")
    }

    /// prefer_not 与跳过都不得被猜成某个值（字典 §4：不自动猜测缺失背景）
    func testPreferNotAndSkipYieldNilNotGuess() {
        let preferNot = outcome([("B01", ["prefer_not"], .answered),
                                 ("B02", ["prefer_not"], .answered)])
        XCTAssertNil(preferNot.isAdult)
        XCTAssertNil(preferNot.nationalities)

        let skipped = outcome([("B01", nil, .skipped), ("B02", nil, .skipped)])
        XCTAssertNil(skipped.isAdult)
        XCTAssertNil(skipped.nationalities)
    }

    func testMinorIsFalseNotNil() {
        XCTAssertEqual(outcome([("B01", ["minor"], .answered)]).isAdult, false,
                       "未成年是明确的 false，不能与「未作答」混同")
    }

    /// 端到端：背景答案 → 资格判定
    func testEligibilityFromBackground() {
        let eligible = outcome([("B01", ["adult"], .answered),
                                ("B02", ["MA"], .answered),
                                ("B03", ["hsk3"], .answered)])
        XCTAssertEqual(ResearchEligibility.evaluate(
            isAdult: eligible.isAdult, nationalities: eligible.nationalities,
            courseStage: eligible.courseStage, consentGranted: true,
            priorUse: .init(status: .new, evidence: .selfReport)), .eligible)

        // 跳过背景表 → pending，不是「不合格」，也不纳入
        let unknown = outcome([("B01", nil, .skipped)])
        XCTAssertEqual(ResearchEligibility.evaluate(
            isAdult: unknown.isAdult, nationalities: unknown.nationalities,
            courseStage: unknown.courseStage, consentGranted: true,
            priorUse: .init(status: .new, evidence: .selfReport)), .pending)
    }
}
