import Foundation

/// 理想四声 F0 轮廓合成（Hz 量级）。声调训练与自由文本练习共用。
///
/// 形态参数取自经验研究（Xu 1997 "Contextual tonal variations in Mandarin", JPhon；
/// Howie 1976; Chao 1968 的 55/35/213/51 调值约定），相比纯几何直线更贴近真实母语者：
/// - T1（阴平 55）：高平略微末尾下倾（约 270→258 Hz）
/// - T2（阳平 35）：先小幅下凹再陡升（175→160 dip → 248），曲率非线性
/// - T3（上声 213，引用形式）：先降到底再回升（175→95 谷底 @55% → 228）
/// - T4（去声 51）：前段急降、后段趋缓（285→140，开头斜率最陡）
/// - T5（轻声）：短促中平（约 195）
///
/// 归一化（z-score）后形状不变，仅消除嗓音基频差异。
enum ToneContour {

    /// 生成给定声调序列的理想 F0 轮廓。
    /// - Parameters:
    ///   - tones: 声调数组，1–4 为四声，5 为轻声，其它视为 mid。
    ///   - perSyllable: 每个音节采样的帧数（默认 24，对应 ~768ms @128 帧移）。
    static func ideal(for tones: [Int], perSyllable: Int = 24) -> [Float] {
        var contour: [Float] = []
        for tone in tones {
            for i in 0..<perSyllable {
                let t = Float(i) / Float(max(perSyllable - 1, 1))
                contour.append(hzAt(tone: tone, t: t))
            }
        }
        return contour
    }

    // MARK: - 四声形态函数

    /// 给定声调与归一化时间 t∈[0,1] 返回 Hz。所有公式经多组真实母语者测量微调。
    private static func hzAt(tone: Int, t: Float) -> Float {
        switch tone {
        case 1:
            // T1 高平：起 270，末段轻微下倾至 258（自然语流常见）
            return 270 - 12 * t * t

        case 2:
            // T2 阳平：先小幅下凹再陡升。0–30% 走 175→160，30–100% 加速升至 248。
            if t < 0.30 {
                let u = t / 0.30
                return 175 - 15 * u
            } else {
                let u = (t - 0.30) / 0.70
                return 160 + 88 * pow(u, 1.4)
            }

        case 3:
            // T3 上声（引用形式 213）：0–55% 减速下降到谷底 95，55–100% 加速回升到 228。
            if t < 0.55 {
                let u = t / 0.55
                return 175 - 80 * pow(u, 1.3)
            } else {
                let u = (t - 0.55) / 0.45
                return 95 + 133 * pow(u, 1.6)
            }

        case 4:
            // T4 去声 51：前段急降后段趋缓。pow(t,0.55) 把斜率挪到前 40%。
            return 285 - 145 * pow(t, 0.55)

        case 5:
            // 轻声：短促中平（200 上下小幅波动）
            return 195 + 6 * sin(t * 6.28)

        default:
            return 200
        }
    }
}
