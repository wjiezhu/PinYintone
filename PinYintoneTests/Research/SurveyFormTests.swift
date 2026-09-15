import XCTest
@testable import PinYintone

/// 问卷定义必须**真的随包发布**且四语齐全——定义没进 bundle 等于没做。
/// 这里刻意用默认的 Bundle.main（即 App bundle），走 App 运行时的真实路径；
/// 若改用测试 bundle，测的就不是「有没有随包发布」这件事了。
final class SurveyFormTests: XCTestCase {

    private let langs = ["zh", "en", "fr", "ar"]

    func testAllThreeFormsShipInBundle() {
        for key in SurveyFormLoader.formKeys {
            XCTAssertNotNil(SurveyFormLoader.load(key),
                            "\(key).json 未随包发布或无法解析")
        }
    }

    func testQuestionCountsMatchResearchDocs() {
        let expected = ["background_v1": 5, "tone_needs_v1": 6, "usability_short_v1": 5]
        for (key, n) in expected {
            let f = SurveyFormLoader.load(key)
            XCTAssertEqual(f?.questions.count, n, "\(key) 应有 \(n) 题")
        }
    }

    func testEveryQuestionAndOptionHasAllFourLanguages() {
        for key in SurveyFormLoader.formKeys {
            guard let f = SurveyFormLoader.load(key) else {
                XCTFail("\(key) 加载失败"); continue
            }
            for q in f.questions {
                for l in langs {
                    XCTAssertNotNil(q.question[l], "\(key).\(q.questionId) 缺 \(l) 题面")
                }
                for o in q.options {
                    for l in langs {
                        XCTAssertNotNil(o.label[l], "\(key).\(q.questionId).\(o.code) 缺 \(l)")
                    }
                }
            }
        }
    }

    /// 互斥与上限规则必须落在定义里，而不是散在 UI 代码中
    func testExclusiveAndLimitRulesArePresent() {
        let pre = SurveyFormLoader.load("tone_needs_v1")!
        let pre02 = pre.questions.first { $0.questionId == "PRE02" }!
        XCTAssertEqual(pre.exclusiveCodes(in: pre02), ["none", "unsure"])

        let pre06 = pre.questions.first { $0.questionId == "PRE06" }!
        XCTAssertEqual(pre06.maxSelections, 2, "PRE06 最多选两项")
        XCTAssertEqual(pre.exclusiveCodes(in: pre06), ["no_expectation"])

        let post = SurveyFormLoader.load("usability_short_v1")!
        let post04 = post.questions.first { $0.questionId == "POST04" }!
        XCTAssertEqual(post.exclusiveCodes(in: post04), ["none", "cannot_recall"])
    }

    /// cannot_judge 不得带分值——字典明确「不计分，不能存为 0」
    func testCannotJudgeHasNoScore() {
        let post = SurveyFormLoader.load("usability_short_v1")!
        for id in ["POST01", "POST02", "POST03"] {
            let q = post.questions.first { $0.questionId == id }!
            let cj = q.options.first { $0.code == "cannot_judge" }!
            XCTAssertNil(cj.value, "\(id).cannot_judge 不得有分值")
            let scored = q.options.compactMap(\.value).sorted()
            XCTAssertEqual(scored, [1, 2, 3, 4, 5], "\(id) 应为 1–5 五档")
        }
    }

    func testFreeTextLimits() {
        let post = SurveyFormLoader.load("usability_short_v1")!
        let p05 = post.questions.first { $0.questionId == "POST05" }!
        XCTAssertEqual(p05.textInput?.maxChars, 500)
        XCTAssertEqual(p05.textInput?.optional, true, "留空不影响 complete")
        let p04 = post.questions.first { $0.questionId == "POST04" }!
        let other = p04.options.first { $0.code == "other" }!
        XCTAssertEqual(other.textInput?.maxChars, 200)
    }
}
