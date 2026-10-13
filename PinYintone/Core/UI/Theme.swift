import SwiftUI
import UIKit

/// 界面的视觉规范（需求 U01，方案 A：简洁专业、浅色、清晰曲线）。
///
/// 颜色全部是**语义色**，浅色与深色各一套，由系统外观自动切换——
/// 不写死白底或白字，深色模式下不会出现看不清的文字。
/// 对比度实测见 docs/UI_CONTRAST.md。
///
/// 功能色只有三种，且**不单靠颜色传达信息**：
/// - 青绿：主要操作、参考曲线
/// - 玫红：学习者自己的曲线
/// - 琥珀：技术失败（配图标与文字）
enum Theme {

    // MARK: 颜色

    /// 页面背景（浅灰）
    static let background = Color(light: 0xF5F7F8, dark: 0x0F1316)
    /// 内容面（白）
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A2026)
    /// 主文字（深灰）
    static let textPrimary = Color(light: 0x20262D, dark: 0xECEFF2)
    /// 次要文字
    static let textSecondary = Color(light: 0x59636E, dark: 0xA9B3BD)
    /// 主要操作与参考曲线（青绿）
    static let accent = Color(light: 0x007F78, dark: 0x3CC2B8)
    /// 放在 accent 色块上的文字 / 图标
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x06201E)
    /// 学习者曲线（玫红）
    static let learner = Color(light: 0xC94461, dark: 0xF08AA2)
    /// 技术失败（琥珀）。用于文字与图标，故取较深的一档以保证对比度
    static let warning = Color(light: 0x8A5300, dark: 0xF2B655)
    /// 录音中（停止键）
    static let recording = Color(light: 0xB3261E, dark: 0xF2857D)
    /// 分隔线与图表辅助线
    static let divider = Color(light: 0xDDE2E6, dark: 0x2C343C)

    static let accentUIColor = UIColor(light: 0x007F78, dark: 0x3CC2B8)

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

    var body: some View {
        Label {
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .accessibilityHidden(true)
        }
        .font(.body.weight(.medium))
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
