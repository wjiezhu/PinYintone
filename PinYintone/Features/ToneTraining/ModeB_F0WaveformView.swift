import SwiftUI

/// 曲线模式：参考曲线（青绿虚线）与学习者曲线（玫红实线）叠加。
/// 输入为已归一化（z-score）的轨迹。
///
/// **显示与评分必须同源**：两条曲线采用与 `DTWAnalyzer` 完全相同的预处理——
/// 丢弃 0（无声）帧——并共用同一条横轴刻度（按有声帧索引等距，分母取两者较长者）。
/// 各自按画布宽度拉伸铺满的话，学习者会把自己的线「目测对齐」到参考线却仍不通过
/// （真实节奏对不上）。现在时长差异如实呈现：说得快，线就短。
///
/// 两条线同时用**颜色和线型**区分（虚线 / 实线），不单靠颜色。
/// 时间方向固定从左到右：阿拉伯语界面下也不镜像，否则升调会被画成降调。
/// 没有有效基频时显示中性的空状态，**不画假曲线**。
struct ModeB_F0WaveformView: View {
    let lexeme: Lexeme
    let studentF0: [Float]
    let referenceF0: [Float]

    // 归一化（z-score）显示范围
    private let vMin: Float = -2.5
    private let vMax: Float = 2.5

    /// 与 DTW 相同的预处理：丢弃 0（无声）帧；NaN/Inf 一并滤掉
    /// （非有限值坐标传入 CoreGraphics 会直接 abort 进程）
    private var reference: [Float] { referenceF0.filter { $0 != 0 && $0.isFinite } }
    private var student: [Float] { studentF0.filter { $0 != 0 && $0.isFinite } }

    var body: some View {
        VStack(spacing: 0) {
            legend
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
            ZStack {
                Canvas { ctx, size in
                    drawGuides(ctx: &ctx, size: size)
                    let ref = reference
                    let stu = student
                    // 共用横轴刻度：分母取两者较长者，短的那条自然提前结束
                    let denom = max(max(ref.count, stu.count) - 1, 1)
                    if ref.count > 1 {
                        ctx.stroke(path(from: ref, denom: denom, in: size),
                                   with: .color(Theme.accent),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [9, 6]))
                    }
                    if stu.count > 1 {
                        ctx.stroke(path(from: stu, denom: denom, in: size),
                                   with: .color(Theme.learner),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                if reference.count < 2 && student.count < 2 {
                    emptyState
                }
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.bottom, Theme.Space.m)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    /// 没有可画的基频：如实说明，不画一条好看的假线
    private var emptyState: some View {
        Text(NSLocalizedString("chart_empty", comment: ""))
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(Theme.Space.l)
    }

    /// 已去 0 帧的有声序列 → 路径。`denom` 为两条曲线共用的横轴分母。
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
            ctx.stroke(line, with: .color(Theme.divider), style: StrokeStyle(lineWidth: 1))
        }
    }

    private var legend: some View {
        HStack(spacing: Theme.Space.l) {
            legendItem(color: Theme.accent, dashed: true,
                       text: NSLocalizedString("legend_native", comment: ""))
            legendItem(color: Theme.learner, dashed: false,
                       text: NSLocalizedString("legend_you", comment: ""))
            Spacer(minLength: 0)
        }
        .font(.footnote)
    }

    private func legendItem(color: Color, dashed: Bool, text: String) -> some View {
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

    private var accessibilitySummary: String {
        NSLocalizedString(student.count > 1 ? "chart_a11y_with_yours" : "chart_a11y_reference_only",
                          comment: "")
    }
}
