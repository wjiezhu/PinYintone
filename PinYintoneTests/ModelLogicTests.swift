import XCTest
@testable import PinYintone

final class ModelLogicTests: XCTestCase {

    // MARK: - A/B 分组（后端均衡随机；离线本地随机兜底）

    func testRandomGroupReturnsValidGroup() {
        for _ in 0..<50 {
            let g = GroupAssignment.randomGroup()
            XCTAssertTrue(g == .staticColor || g == .dynamicF0)
        }
    }

    func testRandomGroupCoversBothOverManyDraws() {
        var seen = Set<ExperimentGroup>()
        for _ in 0..<200 { seen.insert(GroupAssignment.randomGroup()) }
        XCTAssertEqual(seen, [.staticColor, .dynamicF0], "多次抽样应覆盖两组")
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
        // 阴平（55）在自然语流中并非绝对水平：ToneContour 依 Xu (1997) 设计为
        // 高平且末尾轻微下倾（约 270→258 Hz）。故断言"接近水平且不上升"，
        // 而非首尾严格相等。
        let contour = ToneTrainingViewModel.idealContour(for: [1])
        XCTAssertEqual(contour.count, 24)
        let start = contour.first!, end = contour.last!
        XCTAssertLessThanOrEqual(end, start, "阴平不应上升")
        XCTAssertLessThan((start - end) / start, 0.08, "阴平应基本保持高平（降幅 < 8%）")
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
