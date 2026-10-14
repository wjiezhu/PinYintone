import SwiftUI

// 界面的公共构件（需求 U01）。各页面只拼这些东西，不各自发明样式。

extension Theme {
    /// 四声各自的颜色：深松绿、雾蓝、赭、陶红——都取自同一套 token，不另起糖果色。
    /// 只用于声调标记与颜色模式；每个声调同时有**形状**（见 `ToneGlyph`）和数字，
    /// 不单靠颜色区分。
    static func toneColor(_ tone: Int) -> Color {
        switch tone {
        case 1: return Theme.primary
        case 2: return Theme.blueAccent
        case 3: return Theme.ochre
        case 4: return Theme.learnerAccent
        default: return Theme.textSecondary
        }
    }
}

/// 声调的形状标记：把这个声调的走向画成一小段线。
///
/// 一声高平、二声上扬、三声先降后升、四声下降、轻声是一个点。
/// 这是**目标读法的示意**，由声调编号直接画出，不是任何人的实测曲线。
/// 时间方向固定从左到右——由调用方保证外层不随界面方向镜像。
struct ToneGlyph: View {
    let tone: Int
    var lineWidth: CGFloat = 2.5

    var body: some View {
        Canvas { ctx, size in
            let color = Theme.toneColor(tone)
            let inset = lineWidth
            let w = size.width - inset * 2, h = size.height - inset * 2
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: inset + x * w, y: inset + y * h)
            }
            var path = Path()
            switch tone {
            case 1:
                path.move(to: pt(0, 0.2)); path.addLine(to: pt(1, 0.2))
            case 2:
                path.move(to: pt(0, 0.85)); path.addLine(to: pt(1, 0.1))
            case 3:
                path.move(to: pt(0, 0.4))
                path.addQuadCurve(to: pt(0.45, 0.9), control: pt(0.22, 0.9))
                path.addQuadCurve(to: pt(1, 0.2), control: pt(0.7, 0.9))
            case 4:
                path.move(to: pt(0, 0.1)); path.addLine(to: pt(1, 0.9))
            default:
                let r = max(lineWidth, 2)
                ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - r, y: size.height / 2 - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(color))
                return
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// 一个词的声调标记排成一行（按音节从左到右）
struct ToneGlyphRow: View {
    let tones: [Int]
    var glyphSize = CGSize(width: 18, height: 12)
    var lineWidth: CGFloat = 2

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tones.enumerated()), id: \.offset) { _, tone in
                ToneGlyph(tone: tone, lineWidth: lineWidth)
                    .frame(width: glyphSize.width, height: glyphSize.height)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }
}

extension View {
    /// 钉在页面底部的一条栏（问卷的上一题/下一题、知情页的同意/不参加）：
    /// 内容面底色、顶上一条细线，底色延伸到安全区之下。
    func bottomBarSurface() -> some View {
        self
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.m)
            .background(alignment: .top) { Theme.border.frame(height: 1) }
            .background(Theme.background.ignoresSafeArea(edges: .bottom))
    }

    /// 内容面：白底、8pt 圆角、一条细边。不用阴影，不嵌套。
    func surfaceCard(padding: CGFloat = Theme.Space.l, highlighted: Bool = false) -> some View {
        self
            .padding(padding)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius)
                    .strokeBorder(highlighted ? Theme.primary : Theme.border,
                                  lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

/// 按压反馈（需求 U01）：只作用于自身，约 120ms 的轻微变暗与内收，
/// 不改变周围布局、不用厚阴影。开了「减弱动态效果」时只变暗、不位移。
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 首页的功能格（需求 U02）：名称 + 一张线描，**整格可点**。
///
/// 声调格用浅灰绿底加一条深松绿细线，表示它是首要入口；送气格雾蓝浅底；
/// 其余白底描边。不放功能解释或宣传句——名称本身就是说明。
struct ModuleTile: View {
    enum Tone { case primary, blue, plain }

    let title: String
    let kind: ModuleIllustration.Kind
    var tone: Tone = .plain
    /// 一列排布（放大文字）时：名称占满整行，图固定大小放在下面
    var wide = false

    private var fill: Color {
        switch tone {
        case .primary: return Theme.sageSurface
        case .blue: return Theme.blueSurface
        case .plain: return Theme.background
        }
    }

    var body: some View {
        Group {
            if wide {
                // 放大文字时：名称独占一行（长的法语名称不必逐音节折行），图在下面靠前
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    name
                    ModuleIllustration(kind: kind, backdrop: fill)
                        .frame(width: 132)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    name
                    ModuleIllustration(kind: kind, backdrop: fill)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(fill)
        .overlay(alignment: .bottom) {
            if tone == .primary { Theme.primary.frame(height: 3) }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay {
            if tone == .plain {
                RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border)
            }
        }
        .contentShape(Rectangle())
    }

    private var name: some View {
        Text(title)
            .font(.title3.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 短分段切换（曲线 / 颜色）：选中项深松绿加粗并有下划线——不单靠颜色。
struct UnderlineTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String, id: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    VStack(spacing: Theme.Space.s) {
                        Text(option.title)
                            .font(.body.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Theme.primary : Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Capsule()
                            .fill(selected ? Theme.primary : Color.clear)
                            .frame(width: 64, height: 3)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(option.id)
            }
        }
        .overlay(alignment: .bottom) { Theme.border.frame(height: 1) }
    }
}

/// 图标小方块：次级入口、列表行的前导图标
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(Theme.primary)
            .frame(width: size, height: size)
            .background(Theme.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .accessibilityHidden(true)
    }
}

/// 主要操作按钮：整宽、青绿底。文字长时换行，不缩字。
struct PrimaryButtonStyle: ButtonStyle {
    /// 并排的几个按钮要等高时设为 true（由外层用 `fixedSize` 定出行高）
    var fillsHeight = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.onPrimary)
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: fillsHeight ? .infinity : nil)
            .padding(.horizontal, Theme.Space.m)
            .background(Theme.primary.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.38))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 次要操作按钮：整宽、描边
struct SecondaryButtonStyle: ButtonStyle {
    var fillsHeight = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.primary.opacity(isEnabled ? 1 : 0.4))
            .padding(.vertical, Theme.Space.s)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: fillsHeight ? .infinity : nil)
            .padding(.horizontal, Theme.Space.m)
            .background(configuration.isPressed ? Theme.secondaryBackground : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 登录前几页的顶部：应用名称与声纹
struct BrandHeader: View {
    var body: some View {
        BrandWordmark()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 一行可点的入口：图标方块 + 标题 + 副标题 + 箭头
struct EntryRow: View {
    let icon: String
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.s)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: Theme.minTap)
        .contentShape(Rectangle())
    }
}

/// 练习页底部的固定操作栏（需求 U03）：左 · 录音/停止 · 右，三格等宽，录音键恒在正中。
///
/// 钉在安全区之上，待录、录音、分析、反馈、失败任何状态下三个位置都不动。
/// 左右顺序不随界面方向镜像——「示范在左、下一词在右」对所有语言都一样。
/// 栏内文字像系统工具栏一样设了放大上限：再大就会挤掉上面的内容，
/// 完整说明由 VoiceOver 标签给出。
struct PracticeActionBar<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            leading.frame(maxWidth: .infinity)
            center.frame(maxWidth: .infinity)
            trailing.frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xs)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) { Theme.border.frame(height: 1) }
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
        .environment(\.layoutDirection, .leftToRight)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// 操作栏两侧的按钮：图标 + 一个词的说明
struct BarButton: View {
    let icon: String
    /// 图标下的短说明
    let caption: String
    /// VoiceOver 读的完整说明
    let label: String
    var id: String = ""
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(height: 30)
                    .accessibilityHidden(true)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 不可用时整体变淡：位置不动，只是看得出现在点不了
            .opacity(isEnabled ? 1 : 0.32)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap + 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// 操作栏里用不上的格子：留空占位，不移除——否则录音键会横跳
struct BarPlaceholder: View {
    var body: some View {
        Color.clear.frame(height: Theme.minTap + 8)
    }
}

/// 词条小卡：汉字、声调形状、拼音、释义。选词面板用。
struct WordTile: View {
    let lexeme: Lexeme
    let language: String
    var isCurrent = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(alignment: .center, spacing: Theme.Space.s) {
                Text(lexeme.hanzi)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .environment(\.layoutDirection, .leftToRight)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.primary)
                        .accessibilityLabel(NSLocalizedString("word_current", comment: ""))
                } else {
                    ToneGlyphRow(tones: lexeme.tones)
                }
            }
            Text(lexeme.pinyin)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .environment(\.layoutDirection, .leftToRight)
            let gloss = lexeme.glosses(for: language).primary
            if !gloss.isEmpty {
                Text(gloss)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .surfaceCard(padding: Theme.Space.m, highlighted: isCurrent)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// 一组行放在同一块内容面里，行间一条细线（「更多练习」、记录页的一天）
struct GroupedCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // `_VariadicView` 不是公开接口；这里用最朴素的办法：调用方自己在行间放 `RowDivider`
        VStack(spacing: 0) { content }
            .padding(.horizontal, Theme.Space.l)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
    }
}

struct RowDivider: View {
    var body: some View {
        Theme.border.frame(height: 1)
    }
}

extension View {
    /// 内容不满一屏时不回弹。`scrollBounceBehavior` 是 iOS 16.4 才有的，更早的系统保持默认回弹。
    @ViewBuilder
    func bounceOnlyWhenScrollable() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
