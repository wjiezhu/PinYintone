import SwiftUI

/// 模式 B（dynamicF0，实验组）：Canvas 叠加绘制母语者参照（蓝色虚线）与
/// 学习者实时 F0（橙色实线）。对应论文图 2「自我叠加轨迹拟合」。
/// 输入为已归一化（z-score）的轨迹；0 值（无声帧）跳过不绘制。
struct ModeB_F0WaveformView: View {
    let lexeme: Lexeme
    let studentF0: [Float]
    let referenceF0: [Float]

    // 归一化（z-score）显示范围
    private let vMin: Float = -2.5
    private let vMax: Float = 2.5

    var body: some View {
        Canvas { ctx, size in
            drawGuides(ctx: &ctx, size: size)

            if !referenceF0.isEmpty {
                ctx.stroke(
                    path(from: referenceF0, in: size),
                    with: .color(.blue.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 2.5, dash: [10, 6])
                )
            }
            if !studentF0.isEmpty {
                ctx.stroke(
                    path(from: studentF0, in: size),
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) { legend }
    }

    private func path(from track: [Float], in size: CGSize) -> Path {
        var p = Path()
        var started = false
        let n = max(track.count - 1, 1)
        for (i, v) in track.enumerated() where v != 0 {
            let x = CGFloat(i) / CGFloat(n) * size.width
            let clamped = min(max(v, vMin), vMax)
            let norm = CGFloat((clamped - vMin) / (vMax - vMin))
            let y = size.height * (1 - norm)
            if started {
                p.addLine(to: CGPoint(x: x, y: y))
            } else {
                p.move(to: CGPoint(x: x, y: y))
                started = true
            }
        }
        return p
    }

    private func drawGuides(ctx: inout GraphicsContext, size: CGSize) {
        for frac in stride(from: 0.25, through: 0.75, by: 0.25) {
            var line = Path()
            let y = size.height * frac
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(line, with: .color(.gray.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            label(color: .blue, text: NSLocalizedString("legend_native", comment: ""), dashed: true)
            label(color: .orange, text: NSLocalizedString("legend_you", comment: ""), dashed: false)
        }
        .font(.caption2)
        .padding(8)
    }

    private func label(color: Color, text: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 16, height: 3)
                .opacity(dashed ? 0.75 : 1)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
