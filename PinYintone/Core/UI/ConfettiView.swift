import SwiftUI

/// 高分庆祝彩带（纯 SwiftUI Canvas + TimelineView，零第三方依赖）。
/// 彩色碎片从顶部飘落 + 旋转，用于优秀评分的正向反馈。
struct ConfettiView: View {
    private let pieces: [Piece] = (0..<70).map { _ in Piece.random() }
    private let palette: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                for piece in pieces {
                    // 循环下落：0→1 映射到 0→height
                    let progress = ((t * piece.speed + piece.offset)
                        .truncatingRemainder(dividingBy: 1.0))
                    let x = piece.x * size.width + CGFloat(sin(t * piece.sway + piece.offset)) * 14
                    let y = CGFloat(progress) * (size.height + 40) - 20
                    let angle = Angle(radians: t * piece.spin + piece.offset)

                    var rect = ctx
                    rect.translateBy(x: x, y: y)
                    rect.rotate(by: angle)
                    let w: CGFloat = 7, h: CGFloat = 11
                    rect.fill(
                        Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h),
                             cornerRadius: 1.5),
                        with: .color(palette[piece.colorIndex % palette.count].opacity(0.9))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    struct Piece {
        let x: CGFloat
        let speed: Double
        let offset: Double
        let sway: Double
        let spin: Double
        let colorIndex: Int

        static func random() -> Piece {
            Piece(
                x: .random(in: 0...1),
                speed: .random(in: 0.15...0.45),
                offset: .random(in: 0..<(2 * .pi)),
                sway: .random(in: 1.5...3.5),
                spin: .random(in: 1.0...4.0),
                colorIndex: Int.random(in: 0..<7)
            )
        }
    }
}
