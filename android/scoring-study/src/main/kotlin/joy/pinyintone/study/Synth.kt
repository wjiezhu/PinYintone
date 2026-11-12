package joy.pinyintone.study

import kotlin.math.PI
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * 合成学习者 F0 轨迹（帧域：每帧 8 ms，即 128 采样帧移），直接产出「逐帧 YIN 结果」那样的 Hz 序列
 * （无声帧 = 0），再交给生产代码的 clean / normalize。帧域合成省掉了 YIN 的开销，
 * 音频域的真实性由 TTS 那组（真音频走完整 YIN）补上。
 *
 * 声调形态用赵元任五度值（1–5）描述，换算到半音：level 1 = 调域下沿，5 = 上沿。
 */
object Synth {

    enum class Sex { MALE, FEMALE }

    data class Speaker(val keyHz: Float, val rangeSt: Float)

    fun speaker(sex: Sex, rnd: Random) = when (sex) {
        Sex.MALE -> Speaker(keyHz = 115f + rnd.nextFloat() * 30f, rangeSt = 8f + rnd.nextFloat() * 3f)
        Sex.FEMALE -> Speaker(keyHz = 200f + rnd.nextFloat() * 50f, rangeSt = 10f + rnd.nextFloat() * 3f)
    }

    /** 读法：tones 是**实际读出来的**声调（读错调时与目标不同）；flat 表示读平 */
    data class Reading(
        val tones: List<Int>,
        val flat: Boolean = false,
        /** 非末位三声按半上（21）读、3+3 前字变二声；false = 每个三声都读引用式 214 */
        val natural: Boolean = true,
        /** 走势幅度缩放（1 = 正常，0 = 平；0–1 之间是「读得不到位」） */
        val excursion: Float = 1f,
        /** 仅读平时：指定整词漂移（半音，负 = 下滑）；null = 随机 0.3–1.5 半音下倾 */
        val flatDriftSt: Float? = null,
    )

    data class Options(
        val voicedFrames: Int,
        val sex: Sex,
        val jitterSt: Float = 0.12f,
        val wanderSt: Float = 0.25f,
        /** 无声间隔、首尾静音、清辅音扰动、八度错误 */
        val realistic: Boolean = true,
    )

    /** 五度值随时间 t∈[0,1] 的形态。prevTone 用于轻声。 */
    private fun level(tone: Int, t: Float, halfThird: Boolean, prevTone: Int): Float = when (tone) {
        1 -> 5f - 0.25f * t
        2 -> if (t < 0.25f) 3f - 0.4f * (t / 0.25f) else 2.6f + 2.4f * ((t - 0.25f) / 0.75f).pow(1.4f)
        3 -> if (halfThird) 2f - 1f * minOf(1f, t / 0.6f) + 0.2f * maxOf(0f, t - 0.6f)
             else if (t < 0.5f) 2f - 1f * (t / 0.5f).pow(1.2f) else 1f + 3f * ((t - 0.5f) / 0.5f).pow(1.5f)
        4 -> 5f - 4f * t.pow(0.6f)
        5 -> when (prevTone) { 1 -> 2.2f; 2 -> 3f; 3 -> 4f; 4 -> 1.4f; else -> 3f } - 0.3f * t
        else -> 3f
    }

    fun track(reading: Reading, opt: Options, rnd: Random): FloatArray {
        val sp = speaker(opt.sex, rnd)
        val n = reading.tones.size
        // 实际读法（连读变调 / 半上）
        val realized = reading.tones.toMutableList()
        val half = BooleanArray(n)
        if (reading.natural) {
            for (i in 0 until n - 1) {
                if (realized[i] == 3 && reading.tones[i + 1] == 3) realized[i] = 2
                else if (realized[i] == 3) half[i] = true
            }
        }
        // 音节时长（有声帧）分配：轻声短
        val weights = FloatArray(n) { i -> (if (reading.tones[i] == 5) 0.6f else 1f) * (0.8f + 0.45f * rnd.nextFloat()) }
        val wsum = weights.sum()
        val lens = IntArray(n) { maxOf(3, (opt.voicedFrames * weights[it] / wsum).toInt()) }

        // 五度值 → 半音（相对音域中心）
        val st = ArrayList<Float>()
        val sylStart = IntArray(n)
        for (i in 0 until n) {
            sylStart[i] = st.size
            for (k in 0 until lens[i]) {
                val t = k.toFloat() / maxOf(lens[i] - 1, 1)
                val lv = if (reading.flat) 3.2f else level(realized[i], t, half[i], if (i > 0) realized[i - 1] else 0)
                st.add((lv - 3f) / 4f * sp.rangeSt)
            }
        }
        // 协同发音：一阶目标逼近（时间常数约 2–3 帧），音节交界处不跳变
        var x = st[0]
        for (k in st.indices) { x += (st[k] - x) * 0.4f; st[k] = x }
        // 幅度缩放、句调下倾、慢漂移、帧级抖动
        val mean = st.average().toFloat()
        val decl = if (reading.flat) (reading.flatDriftSt?.let { -it } ?: (0.3f + 1.2f * rnd.nextFloat())) else 0.5f * rnd.nextFloat()
        var wander = 0f
        for (k in st.indices) {
            wander = 0.9f * wander + gauss(rnd) * opt.wanderSt * sqrt(1 - 0.81f)
            val t = k.toFloat() / maxOf(st.size - 1, 1)
            st[k] = mean + reading.excursion * (st[k] - mean) - decl * t + wander + gauss(rnd) * opt.jitterSt
        }
        // 半音 → Hz
        var hz = st.map { (sp.keyHz * 2.0.pow(it / 12.0)).toFloat() }.toMutableList()

        if (!opt.realistic) return (List(10) { 0f } + hz + List(10) { 0f }).toFloatArray()

        // 清辅音扰动：后字起首 2 帧略高；八度错误 0.5%
        val out = ArrayList<Float>()
        repeat(8 + rnd.nextInt(15)) { out.add(0f) }
        for (i in 0 until n) {
            if (i > 0 && rnd.nextFloat() < 0.6f) repeat(2 + rnd.nextInt(12)) { out.add(0f) }   // 音节间无声段
            for (k in 0 until lens[i]) {
                var v = hz[sylStart[i] + k]
                if (i > 0 && k < 2) v *= 1.03f
                if (rnd.nextFloat() < 0.005f) v *= if (rnd.nextBoolean()) 2f else 0.5f
                out.add(v.coerceIn(75f, 500f))
            }
        }
        repeat(8 + rnd.nextInt(15)) { out.add(0f) }
        return out.toFloatArray()
    }

    fun gauss(rnd: Random): Float {
        // Box–Muller
        val u = rnd.nextDouble().coerceAtLeast(1e-12); val v = rnd.nextDouble()
        return (sqrt(-2 * kotlin.math.ln(u)) * kotlin.math.cos(2 * PI * v)).toFloat()
    }

    // ── 音频域：谐波重合成（TTS 组用） ──────────────────────────────

    /**
     * 按逐帧 F0 与逐帧幅度重合成音频：有声帧用 3 谐波合成元音，无声帧保留原信号（清辅音、底噪）。
     * 用来把真实 TTS 读音「读平」或「压缩走势」，保留原读音的时长、有声段与停顿。
     */
    fun resynthesize(original: FloatArray, f0PerFrame: FloatArray, hop: Int = 128, frame: Int = 512): FloatArray {
        val out = original.copyOf()
        // 每帧 F0 对应窗口中心；按样本线性插值 F0 与 RMS
        val centers = f0PerFrame.indices.map { it * hop + frame / 2 }
        fun at(arr: FloatArray, s: Int): Float {
            if (arr.isEmpty()) return 0f
            val pos = ((s - frame / 2).toFloat() / hop).coerceIn(0f, (arr.size - 1).toFloat())
            val i = minOf(pos.toInt(), arr.size - 2).coerceAtLeast(0)
            if (arr.size == 1) return arr[0]
            val a = arr[i]; val b = arr[i + 1]
            if (a <= 0f || b <= 0f) return if (pos - i < 0.5f) a else b
            return a + (b - a) * (pos - i)
        }
        val rms = FloatArray(f0PerFrame.size) { k ->
            val s = k * hop; var acc = 0.0
            for (j in s until minOf(s + frame, original.size)) acc += original[j] * original[j]
            sqrt(acc / frame).toFloat()
        }
        var phase = 0.0
        for (s in original.indices) {
            if (s < centers.firstOrNull() ?: 0 || s > (centers.lastOrNull() ?: 0)) continue
            val f = at(f0PerFrame, s)
            if (f <= 0f) continue
            val amp = at(rms, s) * 1.9f
            phase += 2 * PI * f / 16_000
            out[s] = (amp * (0.70 * sin(phase) + 0.25 * sin(2 * phase) + 0.10 * sin(3 * phase))).toFloat()
        }
        return out
    }
}
