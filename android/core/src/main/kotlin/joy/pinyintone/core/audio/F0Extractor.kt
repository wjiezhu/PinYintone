package joy.pinyintone.core.audio

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * YIN 音高检测 + F0 轨迹后处理 + 带下限的 z-score 归一化。
 * 参考：de Cheveigné & Kawahara (2002). YIN, a fundamental frequency estimator.
 * 参数遵循 CLAUDE.md：帧长 512、检测 75–500 Hz、YIN 阈值 0.15、无声帧返回 0.0。
 *
 * 对应 Swift：`PinYintone/Core/Audio/F0Extractor.swift`。
 *
 * 浮点复现说明：Swift 版用 Accelerate 做向量归约（`vDSP_svesq` / `vDSP_meanv`），
 * 其内部求和顺序未公开，不可能逐位复现。这里对应位置一律用 Double 累加后再转 Float，
 * 误差比任何一种 Float 求和顺序都小，与 Swift 的差异只在最后几位。
 * 其余 Swift 里写成逐元素 Float 运算的地方（累积均值、抛物线插值、clean）按原顺序照搬，逐位一致。
 */
class F0Extractor {

    val sampleRate: Float = SAMPLE_RATE
    val minF0: Float = MIN_F0
    val maxF0: Float = MAX_F0
    val yinThreshold: Float = YIN_THRESHOLD

    /** 从单帧（512 samples，16 kHz）提取基频（Hz）；无声/无音高返回 0.0 */
    fun extract(frame: FloatArray): Float {
        val n = frame.size
        val halfN = n / 2
        if (halfN <= 2) return 0f

        // Step 1: 差分函数 d(τ) = Σ_j (x_j − x_{j+τ})²（Swift: vDSP_vsub + vDSP_svesq）
        val d = FloatArray(halfN)
        for (tau in 1 until halfN) {
            val count = n - tau
            var ss = 0.0
            for (i in 0 until count) {
                val delta = frame[i + tau] - frame[i]   // Float 减法，与 vDSP_vsub 相同
                ss += (delta * delta).toDouble()
            }
            d[tau] = ss.toFloat()
        }

        // Step 2: 累积均值归一化 d'(τ) = d(τ) / [(1/τ) Σ_{j≤τ} d(j)]
        val dn = FloatArray(halfN) { 1f }
        var runSum = 0f
        for (tau in 1 until halfN) {
            runSum += d[tau]
            dn[tau] = if (runSum > 0) d[tau] * tau.toFloat() / runSum else 1f
        }

        // Step 3: 绝对阈值法 —— 搜索首个低于阈值的 τ，抛物线插值细化
        val minTau = maxOf(1, (sampleRate / maxF0).toInt())          // 32（500 Hz）
        val maxTau = minOf(halfN - 2, (sampleRate / minF0).toInt())  // 213（75 Hz）
        if (minTau > maxTau) return 0f

        for (tau in minTau..maxTau) {
            if (dn[tau] >= yinThreshold) continue
            // 走到该「凹陷」的局部极小，再做抛物线插值
            var t = tau
            while (t + 1 <= maxTau && dn[t + 1] < dn[t]) t += 1
            val refined = parabolicInterpolation(dn, t)
            return if (refined > 0) sampleRate / refined else 0f
        }
        return 0f  // 无声/无音高帧
    }

    /** 抛物线插值：减少频率量化误差 */
    private fun parabolicInterpolation(d: FloatArray, tau: Int): Float {
        if (tau <= 0 || tau >= d.size - 1) return tau.toFloat()
        val s0 = d[tau - 1]
        val s1 = d[tau]
        val s2 = d[tau + 1]
        val denom = 2 * (2 * s1 - s0 - s2)
        if (abs(denom) <= 1e-6f) return tau.toFloat()
        return tau.toFloat() + (s0 - s2) / denom
    }

    /**
     * F0 轨迹后处理：去孤立尖峰 → 八度纠错 → 中值平滑。
     * 仅修正有声（>0）帧的值；无声帧保持 0（CLAUDE.md：不做插值）。
     */
    fun clean(track: FloatArray): FloatArray {
        if (track.size <= 2) return track.copyOf()
        val out = track.copyOf()

        // 1) 去孤立有声段：连续有声帧 < 3（<24ms）不可能是音节，视为噪声置 0
        var i = 0
        while (i < out.size) {
            if (out[i] > 0) {
                var j = i
                while (j < out.size && out[j] > 0) j += 1
                if (j - i < 3) for (k in i until j) out[k] = 0f
                i = j
            } else {
                i += 1
            }
        }

        // 2) 八度纠错：与近期有声帧中值偏离约 2×/0.5× 时折回（结果须仍在检测范围内）
        val recent = ArrayList<Float>()
        for (k in out.indices) {
            if (out[k] <= 0) continue
            if (recent.size >= 3) {
                val med = recent.sorted()[recent.size / 2]
                if (out[k] > med * 1.8f && out[k] / 2 >= minF0) {
                    out[k] /= 2
                } else if (out[k] < med * 0.55f && out[k] * 2 <= maxF0) {
                    out[k] *= 2
                }
            }
            recent.add(out[k])
            if (recent.size > 9) recent.removeAt(0)
        }

        // 3) 3 点中值平滑（仅连续有声帧内部，不跨无声边界）
        val smoothed = out.copyOf()
        for (k in 1 until out.size - 1) {
            if (out[k - 1] > 0 && out[k] > 0 && out[k + 1] > 0) {
                smoothed[k] = maxOf(minOf(out[k - 1], out[k + 1]),
                                    minOf(maxOf(out[k - 1], out[k + 1]), out[k]))
            }
        }
        return smoothed
    }

    /**
     * 带下限的 z-score 归一化整条 F0 轨迹（per utterance，忽略 0 值帧）：
     * `(x - mean) / max(sd, mean × 0.03)`；无声帧保持 0.0。
     *
     * 下限勿删、勿改成固定 Hz（CLAUDE.md 禁令 13 / 14）：纯 z-score 对平调退化，
     * 会让一声词「读得越平分数越差」；固定 Hz 又会按音域歧视说话人。
     * 详见 docs/LEVEL_TONE_SCORING.md。
     */
    fun normalize(track: FloatArray): FloatArray {
        val voiced = track.filter { it > 0 }
        if (voiced.size <= 1) return FloatArray(track.size)

        // Swift: vDSP_meanv
        var acc = 0.0
        for (v in voiced) acc += v.toDouble()
        val mean = (acc / voiced.size).toFloat()

        // 总体标准差（Swift: centered = voiced - mean，再 vDSP_svesq）
        var sumSqD = 0.0
        for (v in voiced) {
            val c = v - mean
            sumSqD += (c * c).toDouble()
        }
        val sumSq = sumSqD.toFloat()
        val std = sqrt(sumSq / voiced.size.toFloat())

        val floor = mean * NORMALIZATION_FLOOR_RATIO
        val divisor = maxOf(std, floor)
        if (divisor <= 0) return FloatArray(track.size)

        return FloatArray(track.size) { k ->
            val x = track[k]
            if (x > 0) (x - mean) / divisor else 0f
        }
    }

    companion object {
        // CLAUDE.md 锁定参数——不得改动
        const val SAMPLE_RATE: Float = 16_000f
        const val FRAME_SIZE: Int = 512
        const val HOP_SIZE: Int = 128
        const val MIN_F0: Float = 75f
        const val MAX_F0: Float = 500f
        const val YIN_THRESHOLD: Float = 0.15f

        /** 归一化除数下限占均值的比例（≈0.5 个半音）。Swift: `normalizationFloorRatio` */
        const val NORMALIZATION_FLOOR_RATIO: Float = 0.03f
    }
}
