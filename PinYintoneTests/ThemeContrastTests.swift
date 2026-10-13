import XCTest
@testable import PinYintone

/// 界面色值的对比度实测（需求 U01：须实测对比度，不以色值列表代替可读性检查）。
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

    func testTextIsReadableOnBothSurfaces() {
        let h = Theme.Hex.self
        for (bgName, bg) in [("页面背景", h.background), ("内容面", h.surface)] {
            check("主文字", h.textPrimary, on: bgName, bg, atLeast: 4.5)
            check("次要文字", h.textSecondary, on: bgName, bg, atLeast: 4.5)
            check("技术失败文字", h.warning, on: bgName, bg, atLeast: 4.5)
            check("强调色文字（通过状态、链接）", h.accent, on: bgName, bg, atLeast: 4.5)
        }
    }

    func testTextOnAccentButtonIsReadable() {
        check("主按钮上的文字", Theme.Hex.onAccent, on: "主操作色", Theme.Hex.accent, atLeast: 4.5)
    }

    func testCurvesAndControlsStandOutFromTheChartSurface() {
        let h = Theme.Hex.self
        check("参考曲线", h.accent, on: "内容面", h.surface, atLeast: 3)
        check("学习者曲线", h.learner, on: "内容面", h.surface, atLeast: 3)
        check("停止键", h.recording, on: "页面背景", h.background, atLeast: 3)
    }

    /// 两条曲线彼此的区分**不能只靠颜色**。
    ///
    /// 规范指定的青绿与玫红明度几乎相同，互相之间的对比度远低于 3:1——
    /// 色觉障碍或灰度显示下单靠颜色分不开。所以参考必须是虚线、学习者必须是实线。
    func testTheTwoCurvesDifferByLineStyleBecauseColourAloneIsNotEnough() {
        let h = Theme.Hex.self
        XCTAssertNotEqual(h.accent.light, h.learner.light)
        XCTAssertNotEqual(h.accent.dark, h.learner.dark)
        let between = ratio(h.accent.light, h.learner.light)
        XCTAssertLessThan(between, 3, "若两色明度已拉开到 3:1 以上，这条说明可以更新")
        XCTAssertFalse(Theme.Curve.referenceDash.isEmpty, "参考曲线必须是虚线")
        XCTAssertTrue(Theme.Curve.learnerDash.isEmpty, "学习者曲线必须是实线")
        XCTAssertNotEqual(Theme.Curve.referenceDash, Theme.Curve.learnerDash)
    }

    /// 实测值留档：改色值后这里的输出会变，报告里引用的数字要跟着更新
    func testPrintMeasuredContrastRatios() {
        let h = Theme.Hex.self
        let rows: [(String, (light: UInt32, dark: UInt32), (light: UInt32, dark: UInt32))] = [
            ("主文字 / 页面背景", h.textPrimary, h.background),
            ("主文字 / 内容面", h.textPrimary, h.surface),
            ("次要文字 / 页面背景", h.textSecondary, h.background),
            ("次要文字 / 内容面", h.textSecondary, h.surface),
            ("强调色 / 内容面", h.accent, h.surface),
            ("强调色 / 页面背景", h.accent, h.background),
            ("主按钮文字 / 强调色", h.onAccent, h.accent),
            ("学习者曲线 / 内容面", h.learner, h.surface),
            ("技术失败 / 内容面", h.warning, h.surface),
            ("技术失败 / 页面背景", h.warning, h.background),
            ("停止键 / 页面背景", h.recording, h.background),
            ("参考曲线 / 学习者曲线", h.accent, h.learner),
        ]
        for (name, fg, bg) in rows {
            print(String(format: "CONTRAST %@ 浅色 %.2f:1 深色 %.2f:1", name,
                         ratio(fg.light, bg.light), ratio(fg.dark, bg.dark)))
        }
    }
}
