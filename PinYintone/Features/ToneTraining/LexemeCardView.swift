import SwiftUI

/// 目标词卡片：汉字 + 拼音 + 声调序列徽章。声调/自由文本通用。
struct LexemeCardView: View {
    let lexeme: Lexeme

    private let toneColors: [Color] = [.green, .blue, .orange, .red]

    var body: some View {
        VStack(spacing: 8) {
            Text(lexeme.hanzi)
                .font(.system(size: 44, weight: .bold))
            Text(lexeme.pinyin)
                .font(.title3)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(Array(lexeme.tones.enumerated()), id: \.offset) { _, tone in
                    Text("\(tone)")
                        .font(.caption.bold())
                        .frame(width: 22, height: 22)
                        .background(color(for: tone).opacity(0.18))
                        .foregroundStyle(color(for: tone))
                        .clipShape(Circle())
                }
            }

            // 法语释义 + Darija 对译（面向摩洛哥学习者）
            if !lexeme.french.isEmpty || !lexeme.darija.isEmpty {
                VStack(spacing: 2) {
                    Text(lexeme.french)
                        .font(.subheadline.weight(.medium))
                    Text(lexeme.darija)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 2)
            }

            // 考察重点
            if !lexeme.focus.isEmpty {
                Text(lexeme.focus)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func color(for tone: Int) -> Color {
        (1...4).contains(tone) ? toneColors[tone - 1] : .gray
    }
}
