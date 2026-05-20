import SwiftUI

/// 模式 A（staticColor，控制组）：用颜色块 + 方向箭头表示声调，无实时 F0 波形。
/// 低认知负荷；两组通关标准与模式 B 完全一致（DTW ≤ 0.5）。
struct ModeA_StaticView: View {
    let lexeme: Lexeme
    let studentF0: [Float]      // 模式 A 不绘制实时曲线
    let referenceF0: [Float]

    private let toneColors: [Color] = [.green, .blue, .orange, .red]
    private let toneArrows = ["arrow.right", "arrow.up.right", "arrow.down.right", "arrow.down.right"]
    private let toneNames = ["阴平", "阳平", "上声", "去声"]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(lexeme.tones.enumerated()), id: \.offset) { idx, tone in
                VStack(spacing: 10) {
                    Image(systemName: symbol(tone))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(color(tone))
                    Text("\(tone)")
                        .font(.title3.bold())
                    Text(name(tone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(color(tone).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func color(_ tone: Int) -> Color {
        (1...4).contains(tone) ? toneColors[tone - 1] : .gray
    }
    private func symbol(_ tone: Int) -> String {
        // 上声用 V 形近似
        if tone == 3 { return "arrow.down.and.up.right.rectangle" }
        return (1...4).contains(tone) ? toneArrows[tone - 1] : "questionmark"
    }
    private func name(_ tone: Int) -> String {
        (1...4).contains(tone) ? toneNames[tone - 1] : "—"
    }
}
