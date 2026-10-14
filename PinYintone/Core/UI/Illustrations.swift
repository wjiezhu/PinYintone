import SwiftUI

/// 四个功能模块的线描（需求 U01）。
///
/// **全部由代码画出**：原创、矢量、任意尺寸清晰，颜色取自语义 token，
/// 深色外观下自动换色。没有位图，也没有取自任何第三方的图形。
/// 线宽与比例四张一致：墨色为主，深松绿、陶红、雾蓝只作点缀。
///
/// 这些图只是模块的**装饰性标识**——它们不承载信息、不可点、不被朗读；
/// 模块的名称和可点性由外层的按钮与文字给出。图中的声调笔画、波形、
/// 书页线条都是示意，**不是任何人的实测数据**。
struct ModuleIllustration: View {
    enum Kind { case tone, freeText, aspiration, savedWords }

    let kind: Kind
    /// 所在图块的底色：前后叠放的图形（词卡）要用它盖住后面的线
    var backdrop: Color = Theme.background

    var body: some View {
        Canvas { ctx, size in
            // 统一画在一个 4:3 的画框里，居中
            let w = min(size.width, size.height * 4 / 3)
            let h = w * 3 / 4
            let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)
            let frame = Frame(origin: origin, w: w, h: h)
            let line = max(1.6, w / 62)
            switch kind {
            case .tone: drawTone(&ctx, frame, line)
            case .freeText: drawBook(&ctx, frame, line)
            case .aspiration: drawBreath(&ctx, frame, line)
            case .savedWords: drawCards(&ctx, frame, line)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        // 图形有自己的左右（声调走向、气流方向），不随界面方向镜像
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    /// 单位坐标（0…1）到画布坐标
    private struct Frame {
        let origin: CGPoint
        let w: CGFloat
        let h: CGFloat
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * w, y: origin.y + y * h)
        }
    }

    private func stroke(_ ctx: inout GraphicsContext, _ path: Path, _ color: Color,
                        _ width: CGFloat) {
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private func segment(_ f: Frame, _ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: f.p(a.0, a.1))
        path.addLine(to: f.p(b.0, b.1))
        return path
    }

    private func curve(_ f: Frame, _ a: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat),
                       _ b: (CGFloat, CGFloat)) -> Path {
        var path = Path()
        path.move(to: f.p(a.0, a.1))
        path.addQuadCurve(to: f.p(b.0, b.1), control: f.p(c.0, c.1))
        return path
    }

    // MARK: 声调：四个声调的走向 + 一段声纹

    private func drawTone(_ ctx: inout GraphicsContext, _ f: Frame, _ line: CGFloat) {
        let mark = line * 1.5
        // 一声高平、二声上扬、三声先降后升、四声下降
        stroke(&ctx, segment(f, (0.13, 0.17), (0.27, 0.17)), Theme.primary, mark)
        stroke(&ctx, segment(f, (0.35, 0.26), (0.47, 0.09)), Theme.primary, mark)
        var dip = Path()
        dip.move(to: f.p(0.55, 0.11))
        dip.addQuadCurve(to: f.p(0.615, 0.25), control: f.p(0.57, 0.25))
        dip.addQuadCurve(to: f.p(0.68, 0.09), control: f.p(0.655, 0.25))
        stroke(&ctx, dip, Theme.primary, mark)
        stroke(&ctx, segment(f, (0.76, 0.09), (0.88, 0.26)), Theme.primary, mark)

        // 声纹框
        let box = CGRect(origin: f.p(0.12, 0.44),
                         size: CGSize(width: 0.76 * f.w, height: 0.44 * f.h))
        stroke(&ctx, Path(roundedRect: box, cornerRadius: line * 2.2), Theme.textPrimary, line)
        // 声纹：一排长短不一的竖线
        let heights: [CGFloat] = [0.05, 0.10, 0.07, 0.17, 0.27, 0.13, 0.22, 0.31,
                                  0.16, 0.24, 0.11, 0.19, 0.08, 0.12, 0.05]
        let left: CGFloat = 0.21, right: CGFloat = 0.79
        for (i, height) in heights.enumerated() {
            let x = left + (right - left) * CGFloat(i) / CGFloat(heights.count - 1)
            stroke(&ctx, segment(f, (x, 0.66 - height / 2), (x, 0.66 + height / 2)),
                   Theme.textPrimary, line)
        }
    }

    // MARK: 自由文本：摊开的书

    private func drawBook(_ ctx: inout GraphicsContext, _ f: Frame, _ line: CGFloat) {
        var left = Path()
        left.move(to: f.p(0.10, 0.20))
        left.addLine(to: f.p(0.50, 0.28))
        left.addLine(to: f.p(0.50, 0.90))
        left.addLine(to: f.p(0.10, 0.82))
        left.closeSubpath()
        var right = Path()
        right.move(to: f.p(0.50, 0.28))
        right.addLine(to: f.p(0.90, 0.20))
        right.addLine(to: f.p(0.90, 0.82))
        right.addLine(to: f.p(0.50, 0.90))
        stroke(&ctx, left, Theme.textPrimary, line)
        stroke(&ctx, right, Theme.textPrimary, line)

        // 左页一个「文」字
        let glyph = ctx.resolve(inked(Text("文")
            .font(.system(size: f.h * 0.34, weight: .bold)), Theme.textPrimary))
        ctx.draw(glyph, at: f.p(0.30, 0.56), anchor: .center)

        // 右页几行字
        stroke(&ctx, segment(f, (0.60, 0.42), (0.80, 0.38)), Theme.blueAccent, line)
        stroke(&ctx, segment(f, (0.60, 0.53), (0.80, 0.49)), Theme.blueAccent, line)
        stroke(&ctx, curve(f, (0.60, 0.66), (0.70, 0.72), (0.80, 0.61)), Theme.learnerAccent, line)
    }

    // MARK: 送气：侧脸与呼出的气流

    private func drawBreath(_ ctx: inout GraphicsContext, _ f: Frame, _ line: CGFloat) {
        var face = Path()
        face.move(to: f.p(0.25, 0.06))
        face.addQuadCurve(to: f.p(0.31, 0.30), control: f.p(0.33, 0.16))   // 额头到眉
        face.addLine(to: f.p(0.39, 0.45))                                  // 鼻梁
        face.addQuadCurve(to: f.p(0.33, 0.50), control: f.p(0.38, 0.50))   // 鼻底
        face.addLine(to: f.p(0.36, 0.555))                                 // 上唇
        face.addLine(to: f.p(0.32, 0.59))                                  // 口
        face.addLine(to: f.p(0.355, 0.635))                                // 下唇
        face.addQuadCurve(to: f.p(0.31, 0.76), control: f.p(0.30, 0.69))   // 下巴
        face.addQuadCurve(to: f.p(0.19, 0.82), control: f.p(0.27, 0.82))   // 下颌
        face.addLine(to: f.p(0.18, 0.96))                                  // 颈
        stroke(&ctx, face, Theme.textPrimary, line)

        // 气流：从口向右散开
        stroke(&ctx, curve(f, (0.45, 0.55), (0.66, 0.52), (0.88, 0.38)), Theme.learnerAccent, line)
        stroke(&ctx, curve(f, (0.46, 0.585), (0.70, 0.58), (0.93, 0.52)), Theme.textPrimary, line)
        stroke(&ctx, curve(f, (0.46, 0.615), (0.70, 0.64), (0.93, 0.66)), Theme.textPrimary, line)
        stroke(&ctx, curve(f, (0.45, 0.645), (0.66, 0.70), (0.88, 0.80)), Theme.blueAccent, line)
    }

    // MARK: 我的词条：叠放的词卡

    private func drawCards(_ ctx: inout GraphicsContext, _ f: Frame, _ line: CGFloat) {
        // 后面一张，略斜
        var back = Path()
        back.move(to: f.p(0.38, 0.14))
        back.addLine(to: f.p(0.88, 0.20))
        back.addLine(to: f.p(0.84, 0.74))
        back.addLine(to: f.p(0.34, 0.68))
        back.closeSubpath()
        stroke(&ctx, back, Theme.textPrimary, line)
        stroke(&ctx, segment(f, (0.60, 0.34), (0.79, 0.363)), Theme.blueAccent, line)
        stroke(&ctx, segment(f, (0.59, 0.46), (0.78, 0.483)), Theme.textPrimary, line)
        stroke(&ctx, segment(f, (0.58, 0.58), (0.72, 0.597)), Theme.learnerAccent, line)

        // 前面一张，盖住后面的线
        let front = CGRect(origin: f.p(0.12, 0.34),
                           size: CGSize(width: 0.40 * f.w, height: 0.56 * f.h))
        let frontPath = Path(roundedRect: front, cornerRadius: line * 1.6)
        ctx.fill(frontPath, with: .color(backdrop))
        stroke(&ctx, frontPath, Theme.textPrimary, line)
        let glyph = ctx.resolve(inked(Text("词")
            .font(.system(size: f.h * 0.30, weight: .bold)), Theme.textPrimary))
        ctx.draw(glyph, at: CGPoint(x: front.midX, y: front.midY), anchor: .center)
    }
}

/// 品牌声纹：五条长短不一的竖线，深松绿。跟在应用名称后面。
struct BrandMark: View {
    var height: CGFloat = 22

    private static let bars: [CGFloat] = [0.36, 0.72, 1.0, 0.60, 0.30]

    var body: some View {
        HStack(alignment: .center, spacing: height * 0.13) {
            ForEach(Array(Self.bars.enumerated()), id: \.offset) { _, bar in
                Capsule()
                    .fill(Theme.primary)
                    .frame(width: height * 0.13, height: height * bar)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 应用名称 + 声纹
struct BrandWordmark: View {
    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            Text("PinYintone")
                .font(.system(.title2, design: .serif, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            BrandMark()
        }
        // 拉丁字母的应用名不随界面方向倒排
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PinYintone")
        .accessibilityAddTraits(.isHeader)
    }
}

/// 给画布里的文字上色。返回 `Text` 的 `foregroundStyle` 是 iOS 17 才有的，
/// iOS 16（iPhone 8 / X 的最高系统）上用 `foregroundColor`。
func inked(_ text: Text, _ color: Color) -> Text {
    if #available(iOS 17.0, *) {
        return text.foregroundStyle(color)
    }
    return text.foregroundColor(color)
}
