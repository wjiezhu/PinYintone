import XCTest
@testable import PinYintone

final class ModelLogicTests: XCTestCase {

    // MARK: - 受试内 A/B 排程（升级需求 §3.2）






    // MARK: - 阶段与反馈呈现（升级需求 §3.1）

    /// 普通练习的词表是全部声调词条——自愿练习不要求练习词与自测词不重叠（需求 R06）
    @MainActor
    func testPracticePoolIsTheWholeToneLexicon() {
        let pool = ToneSequencer().pool.map(\.id)
        let all = CorpusLoader.shared.lexemes(in: .tone).map(\.id)
        XCTAssertEqual(Set(pool), Set(all))
        XCTAssertEqual(pool.count, all.count)
        let selfTest = Set(CorpusLoader.shared.assessmentPool().map(\.id))
        XCTAssertFalse(selfTest.isEmpty)
        XCTAssertTrue(selfTest.isSubset(of: Set(pool)), "自测词也可以在普通练习里练")
    }

    /// 只有普通练习呈现反馈；自测以及历史上的前测、后测都不呈现
    func testOnlyPracticeShowsFeedback() {
        XCTAssertTrue(TrainingPhase.training.showsFeedback)
        for phase in [TrainingPhase.selfTest, .pretest, .posttest] {
            XCTAssertFalse(phase.showsFeedback, "\(phase)")
            XCTAssertTrue(phase.isAssessment)
        }
        XCTAssertEqual(TrainingPhase.selfTest.rawValue, "self_test")
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
