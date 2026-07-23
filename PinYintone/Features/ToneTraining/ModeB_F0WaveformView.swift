import SwiftUI

/// 模式 B（dynamicF0，实验组）：Canvas 叠加绘制母语者参照（蓝色虚线）与
/// 学习者实时 F0（橙色实线）。对应论文图 2「自我叠加轨迹拟合」。
/// 输入为已归一化（z-score）的轨迹。
///
/// **显示与评分必须同源（P0-5）**：两条曲线采用与 `DTWAnalyzer` 完全相同的
/// 预处理——丢弃 0（无声）帧——并共用同一条横轴刻度（按有声帧索引等距，
/// 分母取两者较长者）。此前各自按画布宽度拉伸铺满，会让学习者把橙线"目测对齐"
/// 到蓝线却仍判 fail（真实节奏对不上），反馈自相矛盾。现在时长差异会如实呈现：
/// 说得过快/过慢，橙线就短/长于蓝线。
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

            // 与 DTW 相同的预处理：丢弃 0（无声）帧；NaN/Inf 一并滤掉
            // （非有限值坐标传入 CoreGraphics 会直接 abort 进程）
            let ref = referenceF0.filter { $0 != 0 && $0.isFinite }
            let stu = studentF0.filter { $0 != 0 && $0.isFinite }
            // 共用横轴刻度：分母取两者较长者，短的那条自然提前结束
            let denom = max(max(ref.count, stu.count) - 1, 1)

            if !ref.isEmpty {
                ctx.stroke(
                    path(from: ref, denom: denom, in: size),
                    with: .color(.blue.opacity(0.75)),
                    style: StrokeStyle(lineWidth: 2.5, dash: [10, 6])
                )
            }
            if !stu.isEmpty {
                ctx.stroke(
                    path(from: stu, denom: denom, in: size),
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) { legend }
    }

    /// 已去 0 帧的有声序列 → 路径。`denom` 为两条曲线共用的横轴分母，
    /// 使二者落在同一时间刻度上（不各自拉伸铺满画布）。
    private func path(from voiced: [Float], denom: Int, in size: CGSize) -> Path {
        var p = Path()
        for (i, v) in voiced.enumerated() {
            let x = CGFloat(i) / CGFloat(denom) * size.width
            let clamped = min(max(v, vMin), vMax)
            let norm = CGFloat((clamped - vMin) / (vMax - vMin))
            let y = size.height * (1 - norm)
            if i == 0 {
                p.move(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
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
