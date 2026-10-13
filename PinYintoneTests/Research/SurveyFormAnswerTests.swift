import XCTest
@testable import PinYintone

/// 由问卷草稿生成逐题答案的规则（需求 R05、字典 §11）。
@MainActor
final class SurveyFormAnswerTests: XCTestCase {

    private func form(_ key: String) throws -> SurveyForm {
        try XCTUnwrap(SurveyFormLoader.bundled[key])
    }

    private func answers(_ key: String, _ draft: SurveyDraft) throws -> [String: SurveyAnswer] {
        let list = SurveyFormView.answers(for: try form(key), draft: draft)
        return Dictionary(uniqueKeysWithValues: list.map { ($0.questionID, $0) })
    }

    /// 已回答、跳过、未作答是三种不同的状态，分别保存
    func testAnsweredSkippedAndNotAnsweredAreDistinct() throws {
        var draft = SurveyDraft()
        draft.selections["POST01"] = ["agree"]
        draft.skipped = ["POST02"]
        let a = try answers("usability_short_v1", draft)

        XCTAssertEqual(a["POST01"]?.state, .answered)
        XCTAssertEqual(a["POST01"]?.optionCodes, ["agree"])
        XCTAssertEqual(a["POST02"]?.state, .skipped)
        XCTAssertNil(a["POST02"]?.optionCodes)
        XCTAssertEqual(a["POST03"]?.state, .notAnswered)
        XCTAssertNil(a["POST03"]?.answeredAt, "没答就没有作答时间")
        XCTAssertEqual(a.count, 5, "每一题都有一条，不漏题")
    }

    /// 「无法判断」是一个选项，是**已回答**；它与跳过不是一回事
    func testCannotJudgeIsAnAnswerNotASkip() throws {
        var draft = SurveyDraft()
        draft.selections["POST02"] = ["cannot_judge"]
        let a = try answers("usability_short_v1", draft)
        XCTAssertEqual(a["POST02"]?.state, .answered)
        XCTAssertEqual(a["POST02"]?.optionCodes, ["cannot_judge"])
    }

    /// 「没有困难」（none）同样是已回答，不能用空值代替
    func testNoneOptionIsAnAnswer() throws {
        var draft = SurveyDraft()
        draft.selections["POST04"] = ["none"]
        XCTAssertEqual(try answers("usability_short_v1", draft)["POST04"]?.optionCodes, ["none"])
    }

    /// 「其他」的补充文字只随被选中的那个选项提交
    func testOtherTextTravelsOnlyWithTheSelectedOption() throws {
        var draft = SurveyDraft()
        draft.selections["POST04"] = ["other", "recording_failed"]
        draft.texts["POST04.other"] = "  按钮太小  "
        var a = try answers("usability_short_v1", draft)
        XCTAssertEqual(a["POST04"]?.textValue, "按钮太小")
        XCTAssertEqual(a["POST04"]?.optionCodes, ["other", "recording_failed"])

        // 草稿里还留着文字，但「其他」已不在选中项里：不得提交
        draft.selections["POST04"] = ["recording_failed"]
        a = try answers("usability_short_v1", draft)
        XCTAssertNil(a["POST04"]?.textValue, "取消「其他」后补充文字残留在了答案里")
    }

    /// 跳过的题不带任何内容，哪怕草稿里之前写过字
    func testSkippedQuestionCarriesNothing() throws {
        var draft = SurveyDraft()
        draft.skipped = ["POST05"]
        let a = try answers("usability_short_v1", draft)
        XCTAssertEqual(a["POST05"]?.state, .skipped)
        XCTAssertNil(a["POST05"]?.textValue)
    }

    /// 自由文本题：写了字就是已回答；只有空白等于没答
    func testFreeTextQuestion() throws {
        var draft = SurveyDraft()
        draft.texts["POST05"] = "希望能调慢示范的速度"
        XCTAssertEqual(try answers("usability_short_v1", draft)["POST05"]?.state, .answered)
        XCTAssertEqual(try answers("usability_short_v1", draft)["POST05"]?.textValue,
                       "希望能调慢示范的速度")
        draft.texts["POST05"] = "   \n "
        XCTAssertEqual(try answers("usability_short_v1", draft)["POST05"]?.state, .notAnswered)
    }

    /// 选项码按固定顺序提交，提交的是**编码**不是显示文字
    func testOptionCodesAreSortedCodesNotLabels() throws {
        var draft = SurveyDraft()
        draft.selections["B02"] = ["MA", "FR"]
        let a = try answers("background_v1", draft)
        XCTAssertEqual(a["B02"]?.optionCodes, ["FR", "MA"])
    }

    /// 国籍：显示名按语言本地化，保存的是固定的 ISO 代码（U07）
    func testCountryNamesAreLocalizedButCodesAreFixed() {
        let names = ["zh", "en", "fr", "ar"].map { CountryPickerSheet.name(for: "MA", language: $0) }
        XCTAssertEqual(Set(names).count, 4, "四种语言下国名应各不相同：\(names)")
        XCTAssertEqual(CountryPickerSheet.name(for: "MA", language: "fr"), "Maroc")
        XCTAssertEqual(CountryPickerSheet.name(for: "MA", language: "en"), "Morocco")
    }

    /// 背景表答案 → 资格所需的派生字段
    func testBackgroundDraftProducesEligibilityInputs() throws {
        var draft = SurveyDraft()
        draft.selections = ["B01": ["adult"], "B02": ["MA"], "B03": ["hsk1"]]
        let list = SurveyFormView.answers(for: try form("background_v1"), draft: draft)
        let outcome = SurveyOutcome(formKey: "background_v1", formVersion: "v", translationVersion: "t",
                                    language: "fr", answers: list,
                                    status: SurveyCenter.status(for: list).rawValue,
                                    startedAt: nil, submittedAt: Date())
        XCTAssertEqual(ResearchEligibility.evaluate(background: outcome, consentGranted: true),
                       .eligible)
        XCTAssertEqual(outcome.status, "partial", "B04、B05 没答：是 partial，不是 complete")
    }

    /// 问卷界面的固定文案跟着问卷自己的语言走，四种语言都有
    func testFormChromeIsAvailableInAllFourLanguages() {
        for key in ["previous", "next", "skip_question", "later", "submit", "decline_survey",
                    "select_one", "select_multiple", "privacy_hint", "search_country"] {
            let texts = ["zh", "en", "fr", "ar"].map { SurveyUIStrings.text(key, $0) }
            XCTAssertEqual(Set(texts).count, 4, "\(key) 在四种语言下应各不相同")
            XCTAssertFalse(texts.contains(key), "\(key) 缺译文")
        }
    }
}
