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
            let refined = parabolicInterpolation(dn, at: tau)
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
