package joy.pinyintone.app.audio

import android.os.Handler
import android.os.Looper
import joy.pinyintone.core.audio.ToneContour
import kotlin.math.PI
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * **只在调试构建与 r8check 里用**的合成麦克风（对应 iOS 的 `SyntheticRecordingSource`）：
 * 模拟器没有人声，用它在模拟器上走通「录音 → 分析 → 结果」整条链路。
 *
 * 以 48 kHz 合成当前词的理想声调轮廓（带谐波的元音），按实时节奏送进与真实麦克风
 * **同一条**处理链（重采样 → 分片 → 帧化 → YIN），所以连降采样也一起验证了。
 *
 * - [Kind.TONES]：按目标声调读 → 应通关
 * - [Kind.FLAT]：读成平调 → 声调词应不通关（一声词另当别论）
 * - [Kind.SILENT]：只有底噪 → 技术失败「没录到声音」
 */
class SyntheticMic(private val kind: Kind, private val tones: () -> List<Int>) : MicSource {

    enum class Kind { TONES, FLAT, SILENT }

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    private var thread: Thread? = null

    override val isRunning: Boolean get() = running
    override val inputSampleRate: Int get() = RATE
    override val sourceName: String get() = "synthetic-${kind.name.lowercase()}"

    override fun start(listener: AudioRecorder.Listener) {
        check(!running)
        running = true
        val pcm = render(tones())
        thread = Thread({
            val chunker = f0Pipeline(RATE) { batch -> main.post { if (running) listener.onF0(batch) } }
            val step = RATE / 50   // 20 ms，按实时节奏送
            var i = 0
            while (running) {
                val buf = ShortArray(step) { k -> pcm.getOrElse(i + k) { 0 } }
                chunker.feed(buf)
                i += step
                Thread.sleep(20)
            }
        }, "pinyintone-synthetic-mic").apply { start() }
    }

    override fun stop() {
        running = false
        thread?.join(500)
        thread = null
    }

    private fun render(tones: List<Int>): ShortArray {
        val out = ArrayList<Short>()
        repeat(RATE / 5) { out.add(0) }                    // 200 ms 静音
        if (kind != Kind.SILENT) {
            var phase = 0.0
            for (t in tones) {
                val contour = ToneContour.ideal(listOf(if (kind == Kind.FLAT) 1 else t), perSyllable = 24)
                val n = (RATE * 0.35).toInt()
                for (k in 0 until n) {
                    val pos = k.toDouble() / n * (contour.size - 1)
                    val hz = if (kind == Kind.FLAT) 230.0 else contour[pos.toInt()].toDouble()
                    phase += 2 * PI * hz / RATE
                    val env = minOf(1.0, k / 480.0, (n - 1 - k) / 480.0)
                    val x = env * (0.4 * sin(phase) + 0.12 * sin(2 * phase) + 0.05 * sin(3 * phase))
                    out.add((x * 32767).roundToInt().toShort())
                }
                repeat(RATE / 20) { out.add(0) }           // 50 ms 音节间隔
            }
        }
        return out.toShortArray()
    }

    private companion object {
        const val RATE = 48_000
    }
}
