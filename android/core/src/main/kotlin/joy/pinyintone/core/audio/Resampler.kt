package joy.pinyintone.core.audio

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/**
 * 流式重采样：把硬件原生采样率（常见 44.1 / 48 kHz）转成 CLAUDE.md 锁定的 16 kHz。
 *
 * 为什么需要：Android 上 `AudioRecord` 以 16 kHz 初始化在部分机型上会失败，
 * 这时用硬件采样率录，再在这里降到 16 kHz（与 iOS 用 `AVAudioConverter` 降采样同一思路，
 * 见 CLAUDE.md 禁令 12）。**评分永远在 16 kHz 上做**，这里只是把输入变成 16 kHz。
 *
 * 算法：Blackman 窗 sinc 低通 + 多相查表。降采样时截止频率取输出奈奎斯特的 90%
 * （16 kHz 输出 → 7.2 kHz），远高于基频上限 500 Hz 及其决定 YIN 的低次谐波，
 * 又足以把 8 kHz 以上的成分在折叠前压下去（测试里 12 kHz → 4 kHz 的混叠被压到 -60 dB 以下）。
 * 每个输出点的权重归一到和为 1，保证直流增益恰为 1。
 *
 * 位置用整数有理数推进（n × inRate / outRate），长时间录音不会累积漂移。
 * 分块送入与一次送入的结果**逐位相同**（测试守着）。
 *
 * 与 iOS 的差别：`AVAudioConverter` 的滤波器实现未公开，两端降采样后的波形
 * 不会逐位相同；差异集中在 7 kHz 以上，对 75–500 Hz 的 F0 估计没有可测影响。
 * 两端分数对照用的是 16 kHz WAV（不经过重采样），不受影响。
 */
class Resampler(val inputRate: Int, val outputRate: Int = TARGET_RATE, zeroCrossings: Int = 24) {

    private val passthrough = inputRate == outputRate
    private val step: Int          // 输入每输出一点前进 inputRate / g（以 outputRate / g 为分母）
    private val phases: Int        // 多相数 = outputRate / g
    private val half: Int          // 每侧的抽头数（输入采样）
    private val table: Array<FloatArray>   // [相位][2*half] 归一化权重

    // 流式状态
    private var buffer = FloatArray(0)
    private var bufferStart = 0L   // buffer[0] 对应的输入绝对下标
    private var outIndex = 0L      // 下一个输出点的序号

    init {
        require(inputRate > 0 && outputRate > 0)
        val g = gcd(inputRate, outputRate)
        step = inputRate / g
        phases = outputRate / g
        // 截止频率（周期 / 输入采样）：降采样时按输出奈奎斯特缩放
        val fc = 0.45 * min(1.0, outputRate.toDouble() / inputRate)
        half = if (passthrough) 0 else kotlin.math.ceil(zeroCrossings / (2 * fc)).toInt()
        table = if (passthrough) emptyArray() else Array(phases) { p -> kernel(p.toDouble() / phases, fc) }
    }

    /** 相位 frac∈[0,1)：输出点落在输入下标 k + frac 处；权重覆盖 k-half+1 .. k+half */
    private fun kernel(frac: Double, fc: Double): FloatArray {
        val w = DoubleArray(2 * half)
        var sum = 0.0
        for (j in 0 until 2 * half) {
            val x = (j - half + 1) - frac            // 抽头相对输出点的位置（输入采样）
            val sinc = if (x == 0.0) 1.0 else sin(2 * PI * fc * x) / (2 * PI * fc * x)
            val t = (x + half) / (2.0 * half)       // 窗口坐标 0..1
            val win = if (t <= 0 || t >= 1) 0.0
                      else 0.42 - 0.5 * cos(2 * PI * t) + 0.08 * cos(4 * PI * t)
            w[j] = sinc * win
            sum += w[j]
        }
        return FloatArray(2 * half) { (w[it] / sum).toFloat() }
    }

    /** 送入一段输入，返回此刻能确定的输出（右侧抽头未到的点留到下一次）。 */
    fun process(input: FloatArray): FloatArray {
        if (passthrough) return input.copyOf()
        buffer += input
        val out = ArrayList<Float>(input.size * outputRate / inputRate + 2)
        val available = bufferStart + buffer.size
        while (true) {
            val num = outIndex * step                 // 输出点位置 × phases
            val k = num / phases                      // 整数部分（输入下标）
            val phase = (num % phases).toInt()
            if (k + half >= available) break          // 右侧抽头还没到
            val w = table[phase]
            val first = k - half + 1
            var acc = 0f
            for (j in 0 until 2 * half) {
                val idx = first + j
                val x = if (idx < bufferStart) 0f else buffer[(idx - bufferStart).toInt()]  // 开头之前补 0
                acc += w[j] * x
            }
            out.add(acc)
            outIndex++
        }
        // 丢掉以后用不到的历史
        val keepFrom = (outIndex * step) / phases - half + 1
        if (keepFrom > bufferStart) {
            val drop = min((keepFrom - bufferStart).toInt(), buffer.size)
            buffer = buffer.copyOfRange(drop, buffer.size)
            bufferStart += drop
        }
        return out.toFloatArray()
    }

    /** 录音结束：清空状态（尾部不足一个滤波器宽度的几毫秒丢弃，与 iOS 丢弃不足一片的尾巴同理）。 */
    fun reset() {
        buffer = FloatArray(0)
        bufferStart = 0
        outIndex = 0
    }

    companion object {
        /** CLAUDE.md 锁定的分析采样率 */
        const val TARGET_RATE = 16_000

        private tailrec fun gcd(a: Int, b: Int): Int = if (b == 0) a else gcd(b, a % b)
    }
}
