import Foundation

/// 理想四声 F0 轮廓合成（Hz 量级）。声调训练与自由文本练习共用。
/// 阴平=高平 / 阳平=上升 / 上声=降后升 / 去声=下降 / 轻声=中平。
enum ToneContour {
    static func ideal(for tones: [Int], perSyllable: Int = 24) -> [Float] {
        let low: Float = 150, high: Float = 280, dip: Float = 110, mid: Float = 200
        var contour: [Float] = []
        for tone in tones {
            for i in 0..<perSyllable {
                let t = Float(i) / Float(perSyllable - 1)
                let hz: Float
                switch tone {
                case 1: hz = high
                case 2: hz = low + (high - low) * t
                case 3: hz = t < 0.5
                    ? low + (dip - low) * (t / 0.5)
                    : dip + (high - dip) * ((t - 0.5) / 0.5)
                case 4: hz = high + (low - high) * t
                default: hz = mid   // 轻声/未知
                }
                contour.append(hz)
            }
        }
        return contour
    }
}
