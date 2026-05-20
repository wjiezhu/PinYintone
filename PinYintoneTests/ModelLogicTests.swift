import XCTest
@testable import PinYintone

final class ModelLogicTests: XCTestCase {

    // MARK: - A/B 分组（论文 4.4）

    func testGroupAssignmentIsStable() {
        // 已分配后多次读取应一致（实验期间不可更改）
        let g1 = GroupAssignment.shared.group
        let g2 = GroupAssignment.shared.group
        XCTAssertEqual(g1, g2, "分组在同一安装内应保持不变")
        XCTAssertTrue(g1 == .staticColor || g1 == .dynamicF0, "分组应为两组之一")
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
