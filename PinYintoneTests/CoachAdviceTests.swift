import XCTest
@testable import PinYintone

/// 教练卡选句逻辑（档案 §4.3：每次反馈最多突出**一个**主要调整方向）。
final class CoachAdviceTests: XCTestCase {

    private func seg(_ index: Int, _ char: String, tone: Int,
                     score: Float, hint: DirectionHint) -> ToneSegmentResult {
        ToneSegmentResult(syllableIndex: index, hanziChar: char, expectedTone: tone,
                          segmentScore: score, directionHint: hint)
    }

    private func result(_ segments: [ToneSegmentResult]) -> FeedbackResult {
        FeedbackResult(dtwScore: 0.4, grade: .needsPractice,
                       attemptNumber: 1, segments: segments)
    }

    func testPicksTheWorstFailingSyllableOnly() {
        // 两个字都没唱对时，只挑分段 DTW 最差的那个——改起来收益最大
        let r = result([
            seg(0, "医", tone: 1, score: 0.55, hint: .shouldStayHigh),
            seg(1, "生", tone: 1, score: 0.90, hint: .shouldStayHigh),
        ])
        XCTAssertEqual(r.coachAdvice.focusChar, "生", "应挑最差的那个字")
        XCTAssertEqual(r.coachAdvice.hint, .shouldStayHigh)
    }

    func testPraisesTheOtherSyllableOnlyWhenItActuallyPassed() {
        let r = result([
            seg(0, "医", tone: 1, score: 0.20, hint: .ok),      // 稳了
            seg(1, "生", tone: 1, score: 0.80, hint: .shouldStayHigh),
        ])
        XCTAssertEqual(r.coachAdvice.focusChar, "生")
        XCTAssertEqual(r.coachAdvice.praiseChar, "医", "另一个字确实通关才夸")
    }

    func testDoesNotPraiseWhenEverySyllableFailed() {
        // 全错还说"很稳"会显得系统没在听
        let r = result([
            seg(0, "医", tone: 1, score: 0.70, hint: .shouldStayHigh),
            seg(1, "生", tone: 1, score: 0.85, hint: .shouldStayHigh),
        ])
        XCTAssertNil(r.coachAdvice.praiseChar)
    }

    func testAllCorrectGivesEncouragementWithoutAFocusChar() {
        let r = result([
            seg(0, "医", tone: 1, score: 0.15, hint: .ok),
            seg(1, "生", tone: 1, score: 0.18, hint: .ok),
        ])
        let advice = r.coachAdvice
        XCTAssertNil(advice.focusChar, "全对时没有要改的字")
        XCTAssertEqual(advice.hint, .ok)
        XCTAssertEqual(advice.hint.coachKey, "coach_all_good")
    }

    func testLowConfidenceSyllableFallsBackToRetryPrompt() {
        // 判定不了方向时给技术性重录提示，不硬编一个可能是错的诊断
        let r = result([seg(0, "喝", tone: 1, score: 0.9, hint: .neutral)])
        XCTAssertEqual(r.coachAdvice.hint.coachKey, "coach_neutral")
    }

    func testEverySingleHintHasACoachTemplate() {
        // 少一条模板 = 线上出现空白提示卡
        for hint in [DirectionHint.ok, .shouldStayHigh, .shouldRise,
                     .shouldDipThenRise, .shouldFall, .neutral] {
            let template = NSLocalizedString(hint.coachKey, comment: "")
            XCTAssertFalse(template.isEmpty, "\(hint) 缺教练文案")
            XCTAssertNotEqual(template, hint.coachKey, "\(hint) 的键没有对应翻译")
        }
    }

    func testOnlyOneDirectionIsEverSurfaced() {
        // 版式约束的类型化表达：CoachAdvice 只有一个 focusChar，堆不进第二条
        let r = result([
            seg(0, "相", tone: 1, score: 0.6, hint: .shouldStayHigh),
            seg(1, "信", tone: 4, score: 0.7, hint: .shouldFall),
        ])
        let advice = r.coachAdvice
        XCTAssertEqual(advice.focusChar, "信")
        XCTAssertEqual(advice.hint, .shouldFall, "只呈现最差那条，另一条不出现")
    }
}
