import XCTest
@testable import PinYintone

/// 受试内 A/B 呈现方式映射：由"词子集 + 被试平衡顺序"决定该词用 A 还是 B。
final class PresentationModeTests: XCTestCase {

    func testStaticColorOrder() {
        // .staticColor 顺序：训练 A 用静态色块，B 用动态曲线
        XCTAssertEqual(
            GroupAssignment.presentationMode(subset: .trainingA, order: .staticColor),
            .staticColor)
        XCTAssertEqual(
            GroupAssignment.presentationMode(subset: .trainingB, order: .staticColor),
            .dynamicF0)
    }

    func testDynamicF0Order() {
        // .dynamicF0 顺序：训练 A 用动态曲线，B 用静态色块（与上互为镜像）
        XCTAssertEqual(
            GroupAssignment.presentationMode(subset: .trainingA, order: .dynamicF0),
            .dynamicF0)
        XCTAssertEqual(
            GroupAssignment.presentationMode(subset: .trainingB, order: .dynamicF0),
            .staticColor)
    }

    func testCounterbalanceIsSymmetric() {
        // 两种顺序下，同一子集的呈现方式恰好相反 → 被试间平衡
        for subset in [LexemeSubset.trainingA, .trainingB] {
            let a = GroupAssignment.presentationMode(subset: subset, order: .staticColor)
            let b = GroupAssignment.presentationMode(subset: subset, order: .dynamicF0)
            XCTAssertNotEqual(a, b, "同一子集在两种平衡顺序下呈现方式应相反")
        }
    }

    func testTestAndNilHaveNoPresentation() {
        // 前后测词与送气词（nil）无 A/B 呈现（裸测）
        XCTAssertNil(GroupAssignment.presentationMode(subset: .test, order: .staticColor))
        XCTAssertNil(GroupAssignment.presentationMode(subset: nil, order: .dynamicF0))
    }

    func testEachTrainingWordGetsAMode() {
        // 语料中每个训练词都应能解出非空呈现方式
        for order in [ExperimentGroup.staticColor, .dynamicF0] {
            for w in CorpusLoader.shared.orderedPool(category: .tone) {
                XCTAssertNotNil(
                    GroupAssignment.presentationMode(subset: w.subset, order: order),
                    "训练词 \(w.id) 应有呈现方式")
            }
        }
    }
}
