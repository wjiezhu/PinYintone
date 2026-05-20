import SwiftUI

/// 蒲公英具身交互：triggerRate 驱动种子飞散。
/// 纯 SwiftUI Canvas + TimelineView，零第三方依赖。
/// triggerRate 越高，越多种子从花盘飞离。
struct DandelionView: View {
    let triggerRate: Float  // 0.0 – 1.0

    // 固定布局的种子（角度 + 半径），由 triggerRate 决定飞散程度
    private let seeds: [Seed] = (0..<48).map { _ in
        Seed(
            angle: .random(in: 0..<(2 * .pi)),
            radius: .random(in: 0.15...0.42),
            phase: .random(in: 0..<(2 * .pi)),
            threshold: .random(in: 0...1)
        )
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let base = min(size.width, size.height)

                // 花茎
                var stem = Path()
                stem.move(to: CGPoint(x: center.x, y: center.y))
                stem.addLine(to: CGPoint(x: center.x, y: size.height))
                ctx.stroke(stem, with: .color(.green.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // 花盘
                let diskR = base * 0.06
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - diskR, y: center.y - diskR,
                                           width: diskR * 2, height: diskR * 2)),
                    with: .color(.yellow.opacity(0.7))
                )

                // 种子
                for seed in seeds {
                    // triggerRate 超过该种子阈值 → 飞散
                    let blown = triggerRate >= Float(seed.threshold)
                    let drift: CGFloat = blown ? CGFloat(triggerRate) * base * 0.55 : 0
                    let float = CGFloat(sin(t * 1.5 + seed.phase)) * (blown ? 6 : 1.5)

                    let r = base * seed.radius + drift
                    let x = center.x + CGFloat(cos(seed.angle)) * r
                    let y = center.y + CGFloat(sin(seed.angle)) * r - drift * 0.4 + float
                    let opacity = Double(blown ? max(0, 1 - triggerRate * 0.6) : 0.9)

                    let dotR: CGFloat = 3
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR,
                                               width: dotR * 2, height: dotR * 2)),
                        with: .color(.white.opacity(opacity))
                    )
                    // 绒毛连线
                    if !blown {
                        var spoke = Path()
                        spoke.move(to: center)
                        spoke.addLine(to: CGPoint(x: x, y: y))
                        ctx.stroke(spoke, with: .color(.white.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 0.5))
                    }
                }
            }
        }
    }

    struct Seed {
        let angle: Double
        let radius: CGFloat
        let phase: Double
        let threshold: Double
    }
}
