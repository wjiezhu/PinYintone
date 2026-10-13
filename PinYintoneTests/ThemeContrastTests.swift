import XCTest
@testable import PinYintone

/// 界面色值的对比度实测（需求 2.3 版 U01：普通文字至少 4.5:1；
/// 浅色模块底、深色模式都要另测，不能套用纯白底上的数值）。
///
/// 按 WCAG 2.x 的相对亮度公式计算。门槛：
/// - 正文与次要文字对其所在底色 ≥ 4.5:1
/// - 图形元素（曲线、图标、按钮底色）对底色 ≥ 3:1
/// 浅色与深色两套都测。改了 `Theme.Hex` 里任何一个值，这里会重新算。
final class ThemeContrastTests: XCTestCase {

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    private func ratio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private typealias Pair = (light: UInt32, dark: UInt32)

    private func check(_ name: String, _ fg: Pair, on bgName: String, _ bg: Pair,
                       atLeast minimum: Double, file: StaticString = #filePath, line: UInt = #line) {
        for (mode, f, b) in [("浅色", fg.light, bg.light), ("深色", fg.dark, bg.dark)] {
            let r = ratio(f, b)
            XCTAssertGreaterThanOrEqual(
                r, minimum,
                "\(mode)：\(name) 在 \(bgName) 上对比度 \(String(format: "%.2f", r)):1，低于 \(minimum):1",
                file: file, line: line)
        }
    }

    /// 文字可能落在的每一种底色
    private var surfaces: [(String, Pair)] {
        let h = Theme.Hex.self
        return [("主背景", h.background), ("次级背景", h.secondaryBackground),
                ("内容面", h.surface), ("声调模块浅底", h.sageSurface),
                ("送气模块浅底", h.blueSurface)]
    }

    func testTextIsReadableOnEverySurface() {
        let h = Theme.Hex.self
        for (bgName, bg) in surfaces {
            check("主文字", h.textPrimary, on: bgName, bg, atLeast: 4.5)
            check("次要文字", h.textSecondary, on: bgName, bg, atLeast: 4.5)
            check("深松绿文字（通过状态、选中项、链接）", h.primary, on: bgName, bg, atLeast: 4.5)
        }
    }

    func testLabelsOnFilledButtonsAreReadable() {
        let h = Theme.Hex.self
        check("主按钮上的文字", h.onPrimary, on: "深松绿", h.primary, atLeast: 4.5)
        check("停止键上的文字", h.onLearnerAccent, on: "陶红", h.learnerAccent, atLeast: 4.5)
    }

    /// 陶红、雾蓝、赭只用于图形（曲线、图标、插图点缀、声调标记），门槛是 3:1。
    /// 它们在浅灰底上不到 4.5:1，所以**不用来写正文**——出错提示的文字用主文字色。
    func testGraphicColoursStandOutFromEverySurface() {
        let h = Theme.Hex.self
        for (bgName, bg) in surfaces {
            check("参考曲线", h.primary, on: bgName, bg, atLeast: 3)
            check("学习者曲线 / 出错图标", h.learnerAccent, on: bgName, bg, atLeast: 3)
            check("雾蓝点缀", h.blueAccent, on: bgName, bg, atLeast: 3)
            check("赭（三声标记）", h.ochre, on: bgName, bg, atLeast: 3)
        }
    }

    /// 规范给的三个实测值（纯白底）：改了基准色这里会报出来
    func testBaselineRatiosMatchTheSpecification() {
        let h = Theme.Hex.self
        XCTAssertEqual(ratio(h.primary.light, 0xFFFFFF), 8.34, accuracy: 0.06)
        XCTAssertEqual(ratio(h.learnerAccent.light, 0xFFFFFF), 4.65, accuracy: 0.06)
        XCTAssertEqual(ratio(h.blueAccent.light, 0xFFFFFF), 4.66, accuracy: 0.06)
    }

    /// 两条曲线彼此的区分**不能只靠颜色**：参考是实线，学习者是虚线。
    func testTheTwoCurvesDifferByLineStyleNotOnlyColour() {
        let h = Theme.Hex.self
        XCTAssertNotEqual(h.primary.light, h.learnerAccent.light)
        XCTAssertNotEqual(h.primary.dark, h.learnerAccent.dark)
        XCTAssertTrue(Theme.Curve.referenceDash.isEmpty, "参考曲线是实线")
        XCTAssertFalse(Theme.Curve.learnerDash.isEmpty, "学习者曲线是虚线")
    }

    /// 实测值留档：改色值后这里的输出会变，报告里引用的数字要跟着更新
    func testPrintMeasuredContrastRatios() {
        let h = Theme.Hex.self
        var rows: [(String, Pair, Pair)] = []
        for (bgName, bg) in surfaces {
            rows.append(("主文字 / \(bgName)", h.textPrimary, bg))
            rows.append(("次要文字 / \(bgName)", h.textSecondary, bg))
            rows.append(("深松绿 / \(bgName)", h.primary, bg))
            rows.append(("陶红 / \(bgName)", h.learnerAccent, bg))
            rows.append(("雾蓝 / \(bgName)", h.blueAccent, bg))
        }
        rows.append(("主按钮文字 / 深松绿", h.onPrimary, h.primary))
        rows.append(("停止键文字 / 陶红", h.onLearnerAccent, h.learnerAccent))
        for (name, fg, bg) in rows {
            print(String(format: "CONTRAST %@ 浅色 %.2f:1 深色 %.2f:1", name,
                         ratio(fg.light, bg.light), ratio(fg.dark, bg.dark)))
        }
    }
}
