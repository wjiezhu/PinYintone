import SwiftUI

/// 实时 F0 曲线画布（关卡 3 专用）。无母语者参照：
/// 灰色虚线 = 理想声调形状，紫色实线 = 学习者实时轨迹。
/// 输入为已归一化（z-score）的轨迹；0 值（无声帧）跳过不绘制。
struct FreeF0Canvas: View {
    let studentF0: [Float]
    let idealToneShape: [Float]
    let tones: [Int]

    private let vMin: Float = -2.5
    private let vMax: Float = 2.5

    var body: some View {
        Canvas { ctx, size in
            // 水平参考线
            for frac in stride(from: 0.25, through: 0.75, by: 0.25) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: size.height * frac))
                line.addLine(to: CGPoint(x: size.width, y: size.height * frac))
                ctx.stroke(line, with: .color(.gray.opacity(0.15)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            if !idealToneShape.isEmpty {
                ctx.stroke(
                    path(from: idealToneShape, in: size),
                    with: .color(.gray.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 2.5, dash: [8, 5])
                )
            }
            if !studentF0.isEmpty {
                ctx.stroke(
                    path(from: studentF0, in: size),
                    with: .color(.purple),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                legendItem(color: .gray, text: NSLocalizedString("freetext_legend_ideal", comment: ""), dashed: true)
                legendItem(color: .purple, text: NSLocalizedString("legend_you", comment: ""), dashed: false)
            }
            .font(.caption2)
            .padding(8)
        }
    }

    private func path(from track: [Float], in size: CGSize) -> Path {
        var p = Path()
        var started = false
        // trim 首尾无声帧：录音前静音会把曲线推到画布中段，与理想形状起点错位
        guard let first = track.firstIndex(where: { $0 != 0 && $0.isFinite }),
              let last = track.lastIndex(where: { $0 != 0 && $0.isFinite }) else { return p }
        let trimmed = Array(track[first...last])
        let n = max(trimmed.count - 1, 1)
        // 同时过滤 NaN/Inf：非有限值坐标传入 CoreGraphics 会直接 abort 进程
        for (i, v) in trimmed.enumerated() where v != 0 && v.isFinite {
            let x = CGFloat(i) / CGFloat(n) * size.width
            let clamped = min(max(v, vMin), vMax)
            let y = size.height * (1 - CGFloat((clamped - vMin) / (vMax - vMin)))
            if started { p.addLine(to: CGPoint(x: x, y: y)) }
            else { p.move(to: CGPoint(x: x, y: y)); started = true }
        }
        return p
    }

    private func legendItem(color: Color, text: String, dashed: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 16, height: 3)
                .opacity(dashed ? 0.7 : 1)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
