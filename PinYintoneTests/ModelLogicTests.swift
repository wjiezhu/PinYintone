import XCTest
@testable import PinYintone

final class ModelLogicTests: XCTestCase {

    // MARK: - A/B 分组（班级码前缀决定）

    func testGroupFromClassCodePrefix() {
        XCTAssertEqual(GroupAssignment.group(forClassCode: "100001"), .staticColor, "1 开头 → A")
        XCTAssertEqual(GroupAssignment.group(forClassCode: "234567"), .dynamicF0, "2 开头 → B")
    }

    func testGroupGuestAndOtherPrefixesDefaultB() {
        XCTAssertEqual(GroupAssignment.group(forClassCode: nil), .dynamicF0, "游客（无码）→ B")
        XCTAssertEqual(GroupAssignment.group(forClassCode: ""), .dynamicF0)
        XCTAssertEqual(GroupAssignment.group(forClassCode: "987654"), .dynamicF0, "其余前缀 → B")
    }

    @MainActor
    func testClassCodeFormatValidation() {
        XCTAssertTrue(UserManager.isValidClassCodeFormat("123456"))
        XCTAssertFalse(UserManager.isValidClassCodeFormat("12345"), "5 位不合法")
        XCTAssertFalse(UserManager.isValidClassCodeFormat("12a456"), "含非数字不合法")
    }

    // MARK: - 理想四声轮廓合成

    @MainActor
    func testIdealContourLength() {
        let contour = ToneTrainingViewModel.idealContour(for: [3, 4])
        XCTAssertEqual(contour.count, 48, "每音节 24 帧，两音节 48 帧")
        XCTAssertFalse(contour.contains(0), "合成轮廓不含无声帧")
    }

    @MainActor
    func testTone1IsLevelHigh() {
        let contour = ToneTrainingViewModel.idealContour(for: [1])
        XCTAssertEqual(contour.count, 24)
        XCTAssertEqual(contour.first!, contour.last!, accuracy: 1e-3, "阴平应为高平调（首尾相等）")
    }

    @MainActor
    func testTone2IsRising() {
        let contour = ToneTrainingViewModel.idealContour(for: [2])
        XCTAssertGreaterThan(contour.last!, contour.first!, "阳平应为上升调")
    }

    @MainActor
    func testTone4IsFalling() {
        let contour = ToneTrainingViewModel.idealContour(for: [4])
        XCTAssertLessThan(contour.last!, contour.first!, "去声应为下降调")
    }

    // MARK: - 反馈模板（缺资源时回退非空）

    func testFeedbackTemplateNonEmpty() {
        for grade in [FeedbackGrade.excellent, .good, .needsPractice, .fail] {
            for lang in ["fr", "zh", "en", "ar"] {
                let text = FeedbackTemplateLoader.shared.template(for: grade, language: lang)
                XCTAssertFalse(text.isEmpty, "\(grade)/\(lang) 反馈不应为空")
            }
        }
    }
}
