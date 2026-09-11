import SwiftUI

/// 目标词卡片：汉字 + 拼音 + 声调徽章 + 释义。声调 / 自由文本通用。
///
/// 「词卡」版式的核心块：一次只回答一个问题——**这次要念什么**。
/// 研究者视角的语料标注不在这里出现（见 body 内注释）。
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

            // 不显示 lexeme.focus：那是语料的"考察重点"标注（硬编码中文），
            // 对四语界面的学习者读不懂，在裸测阶段还等于提前告知这题考什么。
            // 它仍保留在语料与导出数据里，供研究者使用。
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
