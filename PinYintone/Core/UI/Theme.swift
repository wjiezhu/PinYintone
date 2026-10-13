import SwiftUI
import UIKit

/// 界面的视觉规范（需求 U01，方案 A：简洁专业、浅色、清晰曲线）。
///
/// 颜色全部是**语义色**，浅色与深色各一套，由系统外观自动切换——
/// 不写死白底或白字，深色模式下不会出现看不清的文字。
/// 对比度由 `ThemeContrastTests` 实测并守住。
///
/// 功能色只有三种，且**不单靠颜色传达信息**：
/// - 青绿：主要操作、参考曲线
/// - 玫红：学习者自己的曲线
/// - 琥珀：技术失败（配图标与文字）
enum Theme {

    // MARK: 颜色

    /// 色值表（浅色 / 深色）。颜色只在这里定义一次；
    /// `ThemeContrastTests` 直接读这张表实测对比度，改色值时测试会跟着重算。
    enum Hex {
        static let background: (light: UInt32, dark: UInt32) = (0xF5F7F8, 0x0F1316)
        static let surface: (light: UInt32, dark: UInt32) = (0xFFFFFF, 0x1A2026)
        static let textPrimary: (light: UInt32, dark: UInt32) = (0x20262D, 0xECEFF2)
        static let textSecondary: (light: UInt32, dark: UInt32) = (0x59636E, 0xA9B3BD)
        static let accent: (light: UInt32, dark: UInt32) = (0x007F78, 0x3CC2B8)
        static let onAccent: (light: UInt32, dark: UInt32) = (0xFFFFFF, 0x06201E)
        static let learner: (light: UInt32, dark: UInt32) = (0xC94461, 0xF08AA2)
        static let warning: (light: UInt32, dark: UInt32) = (0x8A5300, 0xF2B655)
        static let recording: (light: UInt32, dark: UInt32) = (0xB3261E, 0xF2857D)
        static let divider: (light: UInt32, dark: UInt32) = (0xDDE2E6, 0x2C343C)
    }

    /// 页面背景（浅灰）
    static let background = Color(Hex.background)
    /// 内容面（白）
    static let surface = Color(Hex.surface)
    /// 主文字（深灰）
    static let textPrimary = Color(Hex.textPrimary)
    /// 次要文字
    static let textSecondary = Color(Hex.textSecondary)
    /// 主要操作与参考曲线（青绿）
    static let accent = Color(Hex.accent)
    /// 放在 accent 色块上的文字 / 图标
    static let onAccent = Color(Hex.onAccent)
    /// 学习者曲线（玫红）
    static let learner = Color(Hex.learner)
    /// 技术失败（琥珀）。用于文字与图标，故取较深的一档以保证对比度
    static let warning = Color(Hex.warning)
    /// 录音中（停止键）
    static let recording = Color(Hex.recording)
    /// 分隔线与图表辅助线
    static let divider = Color(Hex.divider)

    // MARK: 曲线线型

    /// 两条曲线的线型。参考是虚线、学习者是实线——**线型是颜色之外的第二个区分通道**：
    /// 青绿与玫红的明度几乎相同（实测对比度约 1.1:1），色觉障碍或灰度显示下
    /// 单靠颜色分不开，所以线型必须不同。`ThemeContrastTests` 守着这一点。
    enum Curve {
        static let referenceDash: [CGFloat] = [9, 6]
        static let learnerDash: [CGFloat] = []
        static let referenceWidth: CGFloat = 2.5
        static let learnerWidth: CGFloat = 3
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
    static let pageMargin: CGFloat = 16
    /// 卡片圆角上限
    static let radius: CGFloat = 8
    /// 交互热区下限
    static let minTap: CGFloat = 44
    /// 录音键直径
    static let recordButton: CGFloat = 64
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
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .accessibilityHidden(true)
        }
        .font(prominent ? .title3.weight(.semibold) : .body.weight(.medium))
        .foregroundStyle(color)
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
        case .success: return Theme.accent
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
