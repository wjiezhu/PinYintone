import SwiftUI

/// 实时 F0 曲线画布（自由文本练习专用）。
/// 深松绿实线 = 理想声调形状，陶红虚线 = 学习者本次轨迹（与声调练习页同一套颜色与线型）。
/// 时间方向固定从左到右，不随界面方向镜像。
/// 输入为已归一化（z-score）的轨迹；0 值（无声帧）跳过不绘制。
struct FreeF0Canvas: View {
    let studentF0: [Float]
    let idealToneShape: [Float]
    let tones: [Int]

    private let vMin: Float = -2.5
    private let vMax: Float = 2.5

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Canvas { ctx, size in
                // 水平辅助线
                for frac in stride(from: 0.0, through: 0.75, by: 0.25) {
                    var line = Path()
                    let y = max(0.5, size.height * frac)
                    line.move(to: CGPoint(x: 0, y: y))
                    line.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(line, with: .color(Theme.border),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                var base = Path()
                base.move(to: CGPoint(x: 0, y: size.height - 0.5))
                base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                ctx.stroke(base, with: .color(Theme.border), style: StrokeStyle(lineWidth: 1))

                if !idealToneShape.isEmpty {
                    ctx.stroke(
                        path(from: idealToneShape, in: size),
                        with: .color(Theme.primary),
                        style: StrokeStyle(lineWidth: Theme.Curve.referenceWidth, lineCap: .round,
                                           lineJoin: .round, dash: Theme.Curve.referenceDash)
                    )
                }
                if !studentF0.isEmpty {
                    ctx.stroke(
                        path(from: studentF0, in: size),
                        with: .color(Theme.learnerAccent),
                        style: StrokeStyle(lineWidth: Theme.Curve.learnerWidth, lineCap: .round,
                                           lineJoin: .round, dash: Theme.Curve.learnerDash)
                    )
                }
            }
            HStack(spacing: Theme.Space.xl) {
                CurveLegendItem(color: Theme.primary, dash: Theme.Curve.referenceDash,
                                text: NSLocalizedString("freetext_legend_ideal", comment: ""))
                CurveLegendItem(color: Theme.learnerAccent, dash: Theme.Curve.learnerDash,
                                text: NSLocalizedString("legend_you", comment: ""))
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, Theme.Space.s)
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
}
