import SwiftUI

/// 实时 F0 曲线画布（自由文本练习专用）。
/// 青绿虚线 = 理想声调形状，玫红实线 = 学习者本次轨迹（与声调练习页同一套颜色与线型）。
/// 时间方向固定从左到右，不随界面方向镜像。
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
                ctx.stroke(line, with: .color(Theme.divider), style: StrokeStyle(lineWidth: 1))
            }

            if !idealToneShape.isEmpty {
                ctx.stroke(
                    path(from: idealToneShape, in: size),
                    with: .color(Theme.accent),
                    style: StrokeStyle(lineWidth: Theme.Curve.referenceWidth,
                                       dash: Theme.Curve.referenceDash)
                )
            }
            if !studentF0.isEmpty {
                ctx.stroke(
                    path(from: studentF0, in: size),
                    with: .color(Theme.learner),
                    style: StrokeStyle(lineWidth: Theme.Curve.learnerWidth, lineCap: .round,
                                       lineJoin: .round, dash: Theme.Curve.learnerDash)
                )
            }
        }
        .padding(.top, 28)
        .padding([.horizontal, .bottom], Theme.Space.m)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(alignment: .topLeading) {
            HStack(spacing: Theme.Space.l) {
                legendItem(color: Theme.accent, text: NSLocalizedString("freetext_legend_ideal", comment: ""), dashed: true)
                legendItem(color: Theme.learner, text: NSLocalizedString("legend_you", comment: ""), dashed: false)
            }
            .font(.footnote)
            .padding(Theme.Space.s)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString(
            studentF0.contains { $0 != 0 } ? "chart_a11y_with_yours" : "chart_a11y_reference_only",
            comment: "")))
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
        HStack(spacing: Theme.Space.xs) {
            Canvas { ctx, size in
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height / 2))
                p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(p, with: .color(color),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                              dash: dashed ? [5, 4] : []))
            }
            .frame(width: 26, height: 10)
            Text(text).foregroundStyle(Theme.textSecondary)
        }
    }
}
