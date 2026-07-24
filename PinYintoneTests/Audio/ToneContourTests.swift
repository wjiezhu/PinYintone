import XCTest
@testable import PinYintone

/// 理想轮廓的声调走向断言（作为 TTS 参照矫正的基准，须保持正确）
final class ToneContourTests: XCTestCase {

    /// 取一段序列首/末三分之一的均值
    private func headTail(_ xs: [Float]) -> (Float, Float) {
        let third = max(1, xs.count / 3)
        let head = xs.prefix(third).reduce(0, +) / Float(third)
        let tail = xs.suffix(third).reduce(0, +) / Float(third)
        return (head, tail)
    }

    func testTone1IsBroadlyLevel() {
        let (h, t) = headTail(ToneContour.ideal(for: [1]))
        XCTAssertLessThan(abs(t - h) / h, 0.10, "阴平应基本高平")
    }

    func testTone2Rises() {
        let (h, t) = headTail(ToneContour.ideal(for: [2]))
        XCTAssertGreaterThan(t, h, "阳平应上升")
    }

    func testTone4Falls() {
        let (h, t) = headTail(ToneContour.ideal(for: [4]))
        XCTAssertLessThan(t, h, "去声应下降")
    }

    /// 1+1 全高平词整体不应有明显下行趋势——这正是 TTS 句调下倾要被矫正掉的原因：
    /// 若参照线整体下滑，学习者会照着把「医生」念成降调。
    func testLevelLevelWordHasNoStrongDownTrend() {
        let contour = ToneContour.ideal(for: [1, 1])
        let (h, t) = headTail(contour)
        XCTAssertLessThan(abs(t - h) / h, 0.10, "1+1 词整体应近似水平")
    }

    /// 4+4 全去声词本来就该整体下行——矫正逻辑必须保留这种真实下降，
    /// 不能被当成句调下倾一并抹掉。
    func testFallingFallingWordGenuinelyTrendsDown() {
        let contour = ToneContour.ideal(for: [4, 4])
        let (h, t) = headTail(contour)
        XCTAssertLessThan(t, h, "4+4 词整体应下行")
    }
}
