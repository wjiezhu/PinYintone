import SwiftUI

/// 颜色模式：每个音节一格，用**颜色 + 声调形状 + 调号 + 调类名**表示目标声调，
/// 不绘制实时 F0 曲线。
///
/// 与曲线模式是**学习者自选的两种显示方式**，不是实验分组：
/// 通关标准完全一致（DTW ≤ 0.5），切换模式不影响评分。
///
/// 无障碍：颜色不是唯一信息通道——每格同时给出形状、调号数字和调类名称，
/// 并为整格提供合并后的 VoiceOver 标签（档案 §4.3）。
struct ModeA_StaticView: View {
    let lexeme: Lexeme
    let studentF0: [Float]      // 颜色模式不绘制实时曲线
    let referenceF0: [Float]

    /// 汉字逐字拆开；字数与声调数对不上时不显示字（不硬凑）
    private var characters: [String] {
        let chars = lexeme.hanzi.map(String.init)
        return chars.count == lexeme.tones.count ? chars : []
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Array(lexeme.tones.enumerated()), id: \.offset) { idx, tone in
                VStack(spacing: Theme.Space.s) {
                    if characters.indices.contains(idx) {
                        Text(characters[idx])
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    ToneGlyph(tone: tone, lineWidth: 5)
                        .frame(width: 64, height: 44)
                    VStack(spacing: 2) {
                        if (1...4).contains(tone) {
                            Text("\(tone)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(Theme.toneColor(tone))
                        }
                        Text(name(tone))
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.Space.xs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.toneColor(tone).opacity(0.10))
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

    /// 调类名随界面语言走
    private func name(_ tone: Int) -> String {
        guard (1...5).contains(tone) else { return "—" }
        return NSLocalizedString("tone_name_\(tone)", comment: "")
    }

    /// "第 1 个字：一声，高平" —— 颜色之外再给一条完整的语音通道
    private func accessibilityLabel(index: Int, tone: Int) -> String {
        guard (1...4).contains(tone) else {
            return String(format: NSLocalizedString("tone_slot_neutral_a11y", comment: ""),
                          index + 1, name(tone))
        }
        let format = NSLocalizedString("tone_slot_a11y", comment: "")
        return String(format: format, index + 1, tone, name(tone))
    }
}
