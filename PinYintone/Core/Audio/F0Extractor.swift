import Accelerate
import Foundation

/// YIN 音高检测算法（精度等价 RAPT，Accelerate.vDSP 加速）
/// 参考：de Cheveigné & Kawahara (2002). YIN, a fundamental frequency estimator.
/// 参数遵循 CLAUDE.md：帧长 512、检测 75–500 Hz、YIN 阈值 0.15、无声帧返回 0.0
final class F0Extractor {

    // CLAUDE.md 锁定参数
    let sampleRate: Float = 16_000
    let minF0: Float = 75            // 检测下限
    let maxF0: Float = 500           // 检测上限
    let yinThreshold: Float = 0.15   // 低于此值判为有声段

    /// 从单帧（512 samples，16 kHz）提取基频（Hz）；无声/无音高返回 0.0
    func extract(frame: [Float]) -> Float {
        let n = frame.count
        let halfN = n / 2
        guard halfN > 2 else { return 0 }

        // Step 1: 差分函数 d(τ) = Σ_j (x_j − x_{j+τ})²
        var d = [Float](repeating: 0, count: halfN)
        frame.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for tau in 1..<halfN {
                let count = n - tau
                var delta = [Float](repeating: 0, count: count)
                // delta = x[i+τ] − x[i]（符号不影响平方和）
                vDSP_vsub(base, 1, base + tau, 1, &delta, 1, vDSP_Length(count))
                var ss: Float = 0
                vDSP_svesq(delta, 1, &ss, vDSP_Length(count))
                d[tau] = ss
            }
        }

        // Step 2: 累积均值归一化 d'(τ) = d(τ) / [(1/τ) Σ_{j≤τ} d(j)]
        var dn = [Float](repeating: 1, count: halfN)
        var runSum: Float = 0
        for tau in 1..<halfN {
            runSum += d[tau]
            dn[tau] = runSum > 0 ? d[tau] * Float(tau) / runSum : 1
        }

        // Step 3: 绝对阈值法 —— 搜索首个低于阈值的 τ，抛物线插值细化
        let minTau = max(1, Int(sampleRate / maxF0))            // 32（500 Hz）
        let maxTau = min(halfN - 2, Int(sampleRate / minF0))    // 213（75 Hz）
        guard minTau <= maxTau else { return 0 }

        for tau in minTau...maxTau where dn[tau] < yinThreshold {
            // 走到该「凹陷」的局部极小，再做抛物线插值（标准 YIN 步骤，提升精度）
            var t = tau
            while t + 1 <= maxTau, dn[t + 1] < dn[t] { t += 1 }
            let refined = parabolicInterpolation(dn, at: t)
            return refined > 0 ? sampleRate / refined : 0
        }
        return 0  // 无声/无音高帧
    }

    /// 抛物线插值：减少频率量化误差
    private func parabolicInterpolation(_ d: [Float], at tau: Int) -> Float {
        guard tau > 0, tau < d.count - 1 else { return Float(tau) }
        let s0 = d[tau - 1], s1 = d[tau], s2 = d[tau + 1]
        let denom = 2 * (2 * s1 - s0 - s2)
        guard abs(denom) > 1e-6 else { return Float(tau) }
        return Float(tau) + (s0 - s2) / denom
    }

    /// F0 轨迹后处理：去孤立尖峰 → 八度纠错 → 中值平滑。
    /// YIN 原始输出常见两类误差：① 冲击噪声产生 1–2 帧的孤立"有声"尖峰；
    /// ② 倍频/半频错误（八度错误）使个别帧跳到 2×/0.5× 真实值。
    /// 二者都会撑大 z-score 的标准差、压扁真实曲线并抬高 DTW 距离。
    /// 仅修正有声（>0）帧的值；无声帧保持 0（CLAUDE.md：不做插值）。
    func clean(_ track: [Float]) -> [Float] {
        guard track.count > 2 else { return track }
        var out = track

        // 1) 去孤立有声段：连续有声帧 < 3（<24ms）不可能是音节，视为噪声置 0
        var i = 0
        while i < out.count {
            if out[i] > 0 {
                var j = i
                while j < out.count, out[j] > 0 { j += 1 }
                if j - i < 3 { for k in i..<j { out[k] = 0 } }
                i = j
            } else {
                i += 1
            }
        }

        // 2) 八度纠错：与近期有声帧中值偏离约 2×/0.5× 时折回（结果须仍在检测范围内）
        var recent: [Float] = []
        for i in 0..<out.count where out[i] > 0 {
            if recent.count >= 3 {
                let med = recent.sorted()[recent.count / 2]
                if out[i] > med * 1.8, out[i] / 2 >= minF0 {
                    out[i] /= 2
                } else if out[i] < med * 0.55, out[i] * 2 <= maxF0 {
                    out[i] *= 2
                }
            }
            recent.append(out[i])
            if recent.count > 9 { recent.removeFirst() }
        }

        // 3) 3 点中值平滑（仅连续有声帧内部，不跨无声边界）
        var smoothed = out
        for i in 1..<(out.count - 1) where out[i - 1] > 0 && out[i] > 0 && out[i + 1] > 0 {
            smoothed[i] = max(min(out[i - 1], out[i + 1]),
                              min(max(out[i - 1], out[i + 1]), out[i]))
        }
        return smoothed
    }

    /// z-score 归一化整条 F0 轨迹（per utterance，忽略 0 值帧）
    /// CLAUDE.md：归一化方式 = z-score per utterance；无声帧保持 0.0
    func normalize(_ track: [Float]) -> [Float] {
        let voiced = track.filter { $0 > 0 }
        guard voiced.count > 1 else { return track.map { _ in 0 } }

        var mean: Float = 0
        vDSP_meanv(voiced, 1, &mean, vDSP_Length(voiced.count))

        // 总体标准差
        let centered = voiced.map { $0 - mean }
        var sumSq: Float = 0
        vDSP_svesq(centered, 1, &sumSq, vDSP_Length(centered.count))
        let std = sqrt(sumSq / Float(voiced.count))
        guard std > 0 else { return track.map { _ in 0 } }

        // 有声帧 → z-score；无声帧（0）保持 0
        return track.map { $0 > 0 ? ($0 - mean) / std : 0 }
    }
}
