import SwiftUI

/// 静态颜色模式：用颜色块 + 方向箭头 + 调号表示目标声调，不绘制实时 F0 曲线。
///
/// 与动态曲线模式是**学习者自选的两种显示方式**，不是实验分组：
/// 通关标准完全一致（DTW ≤ 0.5），切换模式不影响评分。
///
/// 无障碍：颜色不是唯一信息通道——每格同时给出方向箭头、调号数字和调类名称，
/// 并为整格提供合并后的 VoiceOver 标签（档案 §4.3）。
struct ModeA_StaticView: View {
    let lexeme: Lexeme
    let studentF0: [Float]      // 静态模式不绘制实时曲线
    let referenceF0: [Float]

    private let toneColors: [Color] = [
        Color(light: 0x1B7F3B, dark: 0x6FD08C),   // 一声
        Color(light: 0x1F5FBF, dark: 0x7FB0F5),   // 二声
        Color(light: 0x8A5300, dark: 0xF2B655),   // 三声
        Color(light: 0xB3261E, dark: 0xF2857D),   // 四声
    ]
    private let toneArrows = ["arrow.right", "arrow.up.right", "arrow.down.right", "arrow.down.right"]

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            ForEach(Array(lexeme.tones.enumerated()), id: \.offset) { idx, tone in
                VStack(spacing: Theme.Space.s) {
                    Image(systemName: symbol(tone))
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(color(tone))
                        .accessibilityHidden(true)
                    Text("\(tone)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(name(tone))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, Theme.Space.m)
                .background(color(tone).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(accessibilityLabel(index: idx, tone: tone)))
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 音节顺序固定从左到右：阿拉伯语界面下也不镜像，否则「喝水」会被排成「水喝」
        .environment(\.layoutDirection, .leftToRight)
    }

    private func color(_ tone: Int) -> Color {
        (1...4).contains(tone) ? toneColors[tone - 1] : .gray
    }

    private func symbol(_ tone: Int) -> String {
        // 上声用 V 形近似
        if tone == 3 { return "arrow.down.and.up.right.rectangle" }
        return (1...4).contains(tone) ? toneArrows[tone - 1] : "questionmark"
    }

    /// 调类名随界面语言走（原为硬编码中文，法语/阿拉伯语界面下读不懂）
    private func name(_ tone: Int) -> String {
        guard (1...4).contains(tone) else { return "—" }
        return NSLocalizedString("tone_name_\(tone)", comment: "")
    }

    /// "第 1 个字：一声，高平" —— 颜色之外再给一条完整的语音通道
    private func accessibilityLabel(index: Int, tone: Int) -> String {
        let format = NSLocalizedString("tone_slot_a11y", comment: "")
        return String(format: format, index + 1, tone, name(tone))
    }
}
