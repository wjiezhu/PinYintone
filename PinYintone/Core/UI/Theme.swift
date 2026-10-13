import SwiftUI
import UIKit

/// 界面的视觉规范（需求 2.3 版 U01：现代中式，白与墨为主体，深松绿主操作）。
///
/// 颜色全部是**语义 token**，只在这里定义一次，浅色与深色各一套，由系统外观自动切换。
/// 页面里不写色值。对比度由 `ThemeContrastTests` 实测并守住。
///
/// 功能色很少，且**不单靠颜色传达信息**：
/// - 深松绿：主按钮、选中状态、品牌声纹、参考曲线（实线）
/// - 陶红：学习者曲线（虚线）、录音中的停止键、少量插图点缀、出错提示的图标
/// - 雾蓝：次级插图点缀
enum Theme {

    // MARK: 颜色

    /// 色值表（浅色 / 深色）。浅色一列是规范给定的基准值；深色一列是对应的语义适配，
    /// 不是把浅色值照搬过去。`ThemeContrastTests` 直接读这张表实测对比度。
    enum Hex {
        typealias Pair = (light: UInt32, dark: UInt32)
        static let background: Pair = (0xFFFFFF, 0x111514)
        static let secondaryBackground: Pair = (0xF5F7F6, 0x181D1B)
        /// 次级背景之上的内容面（设置、记录里的分组）
        static let surface: Pair = (0xFFFFFF, 0x1D2321)
        static let textPrimary: Pair = (0x202623, 0xECEFED)
        static let textSecondary: Pair = (0x626B66, 0xA9B2AD)
        static let primary: Pair = (0x245743, 0x7CC4A3)
        static let onPrimary: Pair = (0xFFFFFF, 0x0C1A14)
        static let learnerAccent: Pair = (0xB35B4C, 0xE8A193)
        static let onLearnerAccent: Pair = (0xFFFFFF, 0x2A0F0A)
        static let blueAccent: Pair = (0x5C7889, 0x9DB8C8)
        static let sageSurface: Pair = (0xEDF3EE, 0x1A2921)
        static let blueSurface: Pair = (0xEEF2F5, 0x1A242B)
        static let border: Pair = (0xE1E6E3, 0x2C3431)
        /// 颜色模式里三声用的赭色（另外三个声调复用深松绿、雾蓝、陶红）
        static let ochre: Pair = (0x86672D, 0xD6B36A)
    }

    /// 主内容背景（白）
    static let background = Color(Hex.background)
    /// 次级背景（冷浅灰）：设置、记录这类分组页面的底
    static let secondaryBackground = Color(Hex.secondaryBackground)
    /// 次级背景之上的内容面
    static let surface = Color(Hex.surface)
    /// 标题、汉字、正文及主要线描（墨色）
    static let textPrimary = Color(Hex.textPrimary)
    /// 拼音辅助说明、时间和次要标签
    static let textSecondary = Color(Hex.textSecondary)
    /// 主按钮、选中状态、品牌声纹与参考曲线（深松绿）
    static let primary = Color(Hex.primary)
    /// 放在 primary 色块上的文字 / 图标
    static let onPrimary = Color(Hex.onPrimary)
    /// 学习者曲线、录音停止态、少量插图点缀（陶红）
    static let learnerAccent = Color(Hex.learnerAccent)
    /// 放在 learnerAccent 色块上的文字 / 图标（停止键）
    static let onLearnerAccent = Color(Hex.onLearnerAccent)
    /// 次级插图点缀（雾蓝），不用于大面积背景
    static let blueAccent = Color(Hex.blueAccent)
    /// 声调模块浅底
    static let sageSurface = Color(Hex.sageSurface)
    /// 送气模块浅底
    static let blueSurface = Color(Hex.blueSurface)
    /// 模块边界与分隔线。**不能当小字颜色用**
    static let border = Color(Hex.border)
    static let ochre = Color(Hex.ochre)

    /// 出错与技术失败提示的**图标**色：沿用陶红，不另立一种颜色。
    /// 提示文字一律用主文字色——陶红在浅色底上不够 4.5:1。
    static let warning = learnerAccent

    // MARK: 曲线线型

    /// 两条曲线的线型。参考是实线、学习者是虚线——**线型是颜色之外的第二个区分通道**，
    /// 色觉障碍或灰度显示下单靠颜色分不开。`ThemeContrastTests` 守着这一点。
    /// 线型只是画法：不改变曲线形状、归一化、评分或左右时间方向。
    enum Curve {
        static let referenceDash: [CGFloat] = []
        static let learnerDash: [CGFloat] = [8, 6]
        static let referenceWidth: CGFloat = 2.5
        static let learnerWidth: CGFloat = 2.5
    }

    // MARK: 间距与尺寸（4 / 8 / 12 / 16 / 24）

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// 常规横向边距
    static let pageMargin: CGFloat = 20
    /// 图块圆角上限
    static let radius: CGFloat = 6
    /// 交互热区下限
    static let minTap: CGFloat = 44
    /// 录音键直径。里面要放图标和一个词的标签，所以比 64 略大
    static let recordButton: CGFloat = 72
    /// 反馈图高度（正常文字尺寸下）
    static let chartHeight: CGFloat = 220
}

extension UIColor {
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(light: light, dark: dark))
    }

    init(_ hex: (light: UInt32, dark: UInt32)) {
        self.init(light: hex.light, dark: hex.dark)
    }
}

/// 页面内的分组标题：小号、次要色、不抢内容。
struct SectionTitle: View {
    let key: String
    var body: some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 状态行：图标 + 文字。**成功、失败、技术问题都同时给图标和文字**，不单靠颜色。
struct StatusLabel: View {
    enum Kind { case success, neutral, warning }
    let kind: Kind
    let text: String
    /// 结果区的主状态用大一号
    var prominent = false

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(textColor)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
        }
        .font(prominent ? .title3.weight(.semibold) : .body.weight(.medium))
    }

    /// 文字颜色：只有「通过」用深松绿；其余（含出错提示）用主文字色，保证读得清
    private var textColor: Color {
        kind == .success ? Theme.primary : Theme.textPrimary
    }

    private var icon: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .neutral: return "arrow.counterclockwise.circle"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .success: return Theme.primary
        case .neutral: return Theme.textPrimary
        case .warning: return Theme.warning
        }
    }
}

extension Lexeme {
    /// 按界面语言取释义。语料只有法语与摩洛哥阿拉伯语两种释义：
    /// 阿拉伯语界面优先 Darija，其余界面优先法语；另一种作为第二行。
    /// 没有的语言**不现编**。
    func glosses(for language: String) -> (primary: String, secondary: String?) {
        let pair = language == "ar" ? (darija, french) : (french, darija)
        let primary = pair.0.isEmpty ? pair.1 : pair.0
        let secondary = (pair.0.isEmpty || pair.1.isEmpty) ? nil : pair.1
        return (primary, secondary)
    }
}
