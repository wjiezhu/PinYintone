import XCTest
@testable import PinYintone

/// 闸门触发时，呈现给学习者的各路信息必须自洽。
///
/// 历史缺陷：闸门按整词掉调判 fail，但逐字 DTW 可能都在通关线内，
/// 于是教练卡按逐字诊断得出"这次都念稳了"，与"不通关"同屏矛盾。
final class GateFeedbackConsistencyTests: XCTestCase {

    /// 构造一个"逐字都通关"的分段结果，模拟闸门触发但 DTW 很好的情形
    private func allPassingSegments() -> [ToneSegmentResult] {
        (0..<2).map {
            ToneSegmentResult(syllableIndex: $0, hanziChar: ["参", "加"][$0],
                              expectedTone: 1, segmentScore: 0.2, directionHint: .ok)
        }
    }

    func testGatedResultDoesNotClaimAllGood() {
        let gated = FeedbackResult(dtwScore: 0.2, levelToneDropped: true,
                                   grade: .fail, attemptNumber: 1,
                                   segments: allPassingSegments())
        XCTAssertEqual(gated.coachAdvice.hint, .wordDropping,
                       "闸门拦下时必须说整词掉调，不能说全对")
        XCTAssertNotEqual(gated.coachAdvice.hint, .ok)
        XCTAssertNil(gated.coachAdvice.praiseChar, "不通关时不应夸奖")
    }

    func testGatedScoreIsBelowPassMark() {
        let gated = FeedbackResult(dtwScore: 0.2, levelToneDropped: true,
                                   grade: .fail, attemptNumber: 1,
                                   segments: allPassingSegments())
        XCTAssertLessThan(gated.score, 60,
                          "不通关却显示 \(gated.score) 分（60 = 通关线）会自相矛盾")
    }

    func testUngatedResultIsUnaffected() {
        let normal = FeedbackResult(dtwScore: 0.2, grade: .excellent,
                                    attemptNumber: 1, segments: allPassingSegments())
        XCTAssertEqual(normal.coachAdvice.hint, .ok, "未触发闸门时行为不变")
        XCTAssertGreaterThan(normal.score, 60)
    }

    /// 整词句式不得含 %@ 占位符——focusChar 为 nil 时会原样显示出来
    func testWordLevelTemplateHasNoPlaceholder() {
        let template = NSLocalizedString(DirectionHint.wordDropping.coachKey, comment: "")
        XCTAssertFalse(template.contains("%@"),
                       "整词提示没有可归咎的单字，模板不能带占位符：\(template)")
        XCTAssertNotEqual(template, DirectionHint.wordDropping.coachKey, "本地化键应已翻译")
    }
}
