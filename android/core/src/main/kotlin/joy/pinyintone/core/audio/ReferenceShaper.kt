package joy.pinyintone.core.audio

import kotlin.math.abs
import kotlin.math.sqrt

/**
 * 母语者参照曲线的提取与整形：逐帧提 F0 → clean → 参照专用重平滑 →（给了声调时）
 * 去多余下倾 → 向理想轮廓混合 → 走向矛盾校验 → 归一化。
 *
 * 对应 Swift：`PinYintone/Core/Audio/SpeechService.swift` 里与平台无关的那部分
 * （`f0Track` / `smoothReference` / `blendTowardIdeal` / `removeExcessDeclination` /
 * `contourContradictsTones` 及 `meanSD` / `slope` / `resample` / `medianFilter` / `movingAverage`）。
 * 音频解码、TTS 合成留在平台层；这里只吃 16 kHz 单声道 Float 采样。
 *
 * 这些函数在 Swift 里全是逐元素 Float 运算，按原顺序照搬，给定相同的 Hz 输入逐位一致。
 */
class ReferenceShaper(private val f0Extractor: F0Extractor = F0Extractor()) {

    /**
     * 逐帧提 F0 → clean → 重平滑 →（tones 非空时）去下倾、混合、校验 → normalize。
     * 有声帧不足 3 或走向与目标声调矛盾时返回空数组（调用方回退到理想轮廓）。
     * @param tones 目标声调。真人录音传空（孤立字本调，不做下倾矫正）。
     */
    fun f0Track(samples: FloatArray, tones: List<Int>): FloatArray {
        val frames = AudioFramer.frames(samples)   // 512 帧长 / 128 帧移，CLAUDE.md 锁定
        val hz = FloatArray(frames.size) { f0Extractor.extract(frames[it]) }
        val voicedCount = hz.count { it > 0 }
        if (voicedCount < 3) return FloatArray(0)

        var cleaned = smoothReference(f0Extractor.clean(hz))
        if (tones.isNotEmpty()) {
            cleaned = removeExcessDeclination(cleaned, tones)
            cleaned = blendTowardIdeal(cleaned, tones)
            if (contourContradictsTones(cleaned, tones)) return FloatArray(0)
        }
        return f0Extractor.normalize(cleaned)
    }

    /** 参照专用重平滑：在连续有声段**内部**做加宽中值 + 三点滑动平均，不跨无声边界。 */
    fun smoothReference(track: FloatArray, window: Int = 5): FloatArray {
        val out = track.copyOf()
        var i = 0
        while (i < track.size) {
            if (track[i] <= 0) { i += 1; continue }
            var j = i
            while (j < track.size && track[j] > 0) j += 1
            val run = track.copyOfRange(i, j)
            if (run.size >= 3) {
                val smoothed = movingAverage(medianFilter(run, window), 3)
                smoothed.copyInto(out, i)
            }
            i = j
        }
        return out
    }

    /**
     * 向理想轮廓混合：各自对齐均值后按 alpha 加权（只对齐均值，保留理想轮廓自身幅度）。
     * @param alpha 原曲线权重（其余给理想轮廓）。
     */
    fun blendTowardIdeal(track: FloatArray, tones: List<Int>, alpha: Float = 0.55f): FloatArray {
        if (tones.isEmpty()) return track.copyOf()
        val positions = track.indices.filter { track[it] > 0 }
        val n = positions.size
        if (n < 4) return track.copyOf()

        val tts = FloatArray(n) { track[positions[it]] }
        val (tMean, _) = meanSD(tts) ?: return track.copyOf()
        val ideal = resample(ToneContour.ideal(tones), n)
        if (ideal.size != n) return track.copyOf()
        val (iMean, _) = meanSD(ideal) ?: return track.copyOf()

        val out = track.copyOf()
        for (k in 0 until n) {
            val aligned = ideal[k] - iMean + tMean
            out[positions[k]] = maxOf(alpha * tts[k] + (1 - alpha) * aligned, 1f)
        }
        return out
    }

    /**
     * 消除多余下倾：以同声调序列的理想轮廓为基准，只减去原曲线相对理想轮廓**多出来**的斜率
     * （Hz 域比较），以序列中点为轴校正。
     */
    fun removeExcessDeclination(track: FloatArray, tones: List<Int>): FloatArray {
        val positions = track.indices.filter { track[it] > 0 }
        val n = positions.size
        if (n < 6) return track.copyOf()

        val ttsHz = FloatArray(n) { track[positions[it]] }
        val ideal = resample(ToneContour.ideal(tones), n)
        if (ideal.size != n) return track.copyOf()

        val xs = FloatArray(n) { it.toFloat() }
        val excess = slope(xs, ttsHz) - slope(xs, ideal)   // Hz / 帧
        if (abs(excess) <= 1e-3f) return track.copyOf()

        val mid = (n - 1).toFloat() / 2
        val out = track.copyOf()
        for (k in 0 until n) {
            out[positions[k]] = maxOf(ttsHz[k] - excess * (k.toFloat() - mid), 1f)  // 保底为正
        }
        return out
    }

    /** 校验整形后的走向是否与目标声调**明显矛盾**；半数以上音节矛盾才判定不可信。 */
    fun contourContradictsTones(track: FloatArray, tones: List<Int>): Boolean {
        val voiced = track.filter { it > 0 }.toFloatArray()
        val n = tones.size
        if (n <= 0 || voiced.size < n * 3) return false
        val (_, sd) = meanSD(voiced) ?: return false
        if (sd <= 0) return false

        var checked = 0
        var contradictions = 0
        for (i in 0 until n) {
            val seg = voiced.copyOfRange(voiced.size * i / n, voiced.size * (i + 1) / n)
            if (seg.size < 3) continue
            val third = maxOf(1, seg.size / 3)
            var headSum = 0f
            for (k in 0 until third) headSum += seg[k]
            var tailSum = 0f
            for (k in seg.size - third until seg.size) tailSum += seg[k]
            val head = headSum / third.toFloat()
            val tail = tailSum / third.toFloat()
            val deltaZ = (tail - head) / sd

            when (tones[i]) {
                2 -> { checked += 1; if (deltaZ < -0.6f) contradictions += 1 }   // 该升却明显降
                4 -> { checked += 1; if (deltaZ > 0.6f) contradictions += 1 }    // 该降却明显升
                1 -> { checked += 1; if (abs(deltaZ) > 1.6f) contradictions += 1 } // 该平却大起大落
                else -> Unit   // 三声（曲折）与轻声不做方向判定
            }
        }
        return checked > 0 && contradictions * 2 > checked
    }

    // MARK: 数值小工具（与 Swift 同为 Float 顺序累加）

    /** 中值滤波（窗口为奇数，边界收缩） */
    private fun medianFilter(xs: FloatArray, window: Int): FloatArray {
        val w = maxOf(3, window or 1)
        val half = w / 2
        if (xs.size <= w) return xs.copyOf()
        return FloatArray(xs.size) { i ->
            val lo = maxOf(0, i - half)
            val hi = minOf(xs.size - 1, i + half)
            val slice = xs.copyOfRange(lo, hi + 1).also { it.sort() }
            slice[slice.size / 2]
        }
    }

    /** 滑动平均（边界收缩） */
    private fun movingAverage(xs: FloatArray, window: Int): FloatArray {
        val half = maxOf(1, window) / 2
        if (xs.size <= window) return xs.copyOf()
        return FloatArray(xs.size) { i ->
            val lo = maxOf(0, i - half)
            val hi = minOf(xs.size - 1, i + half)
            var sum = 0f
            for (k in lo..hi) sum += xs[k]
            sum / (hi - lo + 1).toFloat()
        }
    }

    private fun meanSD(xs: FloatArray): Pair<Float, Float>? {
        if (xs.isEmpty()) return null
        var s = 0f
        for (x in xs) s += x
        val m = s / xs.size.toFloat()
        var v = 0f
        for (x in xs) v += (x - m) * (x - m)
        v /= xs.size.toFloat()
        return m to sqrt(v)
    }

    /** 最小二乘斜率 */
    private fun slope(xs: FloatArray, ys: FloatArray): Float {
        if (xs.size != ys.size || xs.size <= 1) return 0f
        var sx = 0f
        for (x in xs) sx += x
        val mx = sx / xs.size.toFloat()
        var sy = 0f
        for (y in ys) sy += y
        val my = sy / ys.size.toFloat()
        var num = 0f
        var den = 0f
        for (i in xs.indices) {
            val dx = xs[i] - mx
            num += dx * (ys[i] - my)
            den += dx * dx
        }
        return if (den > 0) num / den else 0f
    }

    /** 线性插值重采样到指定点数 */
    private fun resample(xs: FloatArray, n: Int): FloatArray {
        if (xs.size < 2 || n < 2) return xs.copyOf()
        return FloatArray(n) { k ->
            val pos = k.toFloat() / (n - 1).toFloat() * (xs.size - 1).toFloat()
            val i = minOf(pos.toInt(), xs.size - 2)
            xs[i] + (xs[i + 1] - xs[i]) * (pos - i.toFloat())
        }
    }
}
