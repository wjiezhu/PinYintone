package joy.pinyintone.core.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.log10
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

class ResamplerTest {

    private fun sine(freq: Double, rate: Int, seconds: Double, amp: Double = 0.5) =
        FloatArray((rate * seconds).toInt()) { (amp * sin(2 * PI * freq * it / rate)).toFloat() }

    private fun rms(x: FloatArray, from: Int = 0, to: Int = x.size): Double {
        var s = 0.0
        for (i in from until to) s += x[i].toDouble() * x[i]
        return sqrt(s / (to - from))
    }

    /** 中段若干帧的 YIN 中位数 */
    private fun pitch(x16k: FloatArray): Float {
        val f0 = F0Extractor()
        val hz = AudioFramer.frames(x16k).drop(5).dropLast(5).map { f0.extract(it) }.sorted()
        return hz[hz.size / 2]
    }

    @Test
    fun passthroughAt16k() {
        val x = sine(200.0, 16_000, 0.1)
        assertArrayEquals(x, Resampler(16_000).process(x), 0f)
    }

    @Test
    fun commonHardwareRatesKeepPitch() {
        for (rate in listOf(48_000, 44_100, 32_000, 22_050, 8_000)) {
            for (freq in listOf(110.0, 220.0, 330.0)) {
                val out = Resampler(rate).process(sine(freq, rate, 0.5))
                // 长度 ≈ 输入时长 × 16 kHz（滤波器右侧还没到的几毫秒留在缓冲里）
                assertEquals("$rate Hz 输出长度", 8_000.0, out.size.toDouble(), 120.0)
                // 与直接在 16 kHz 合成的同一正弦比（YIN 对纯正弦本身有几 Hz 的偏差，与重采样无关）
                val native = pitch(sine(freq, 16_000, 0.5))
                assertEquals("$rate Hz 输入、$freq Hz 正弦", native, pitch(out), 0.5f)
            }
        }
    }

    @Test
    fun passbandGainIsUnity() {
        for (rate in listOf(48_000, 44_100)) {
            val out = Resampler(rate).process(sine(1_000.0, rate, 0.5))
            val db = 20 * log10(rms(out, 400, out.size - 400) / (0.5 / sqrt(2.0)))
            assertEquals("$rate Hz 1 kHz 增益", 0.0, db, 0.1)
        }
    }

    @Test
    fun aliasesAreSuppressed() {
        // 48 kHz 下的 12 kHz 正弦不滤就会折叠到 4 kHz；必须压到 -60 dB 以下
        for ((rate, freq) in listOf(48_000 to 12_000.0, 44_100 to 10_000.0, 48_000 to 9_000.0)) {
            val out = Resampler(rate).process(sine(freq, rate, 0.5))
            val db = 20 * log10(rms(out, 400, out.size - 400) / (0.5 / sqrt(2.0)) + 1e-12)
            assertTrue("$rate Hz 输入的 $freq Hz 残留 $db dB", db < -60)
        }
    }

    @Test
    fun chunkedEqualsOneShot() {
        val rnd = Random(7)
        for (rate in listOf(48_000, 44_100, 8_000)) {
            val x = FloatArray(rate / 2) { rnd.nextFloat() * 2 - 1 }
            val whole = Resampler(rate).process(x)
            val r = Resampler(rate)
            val parts = ArrayList<Float>()
            var i = 0
            while (i < x.size) {
                val n = rnd.nextInt(1, 3000)
                parts.addAll(r.process(x.copyOfRange(i, minOf(i + n, x.size))).toList())
                i += n
            }
            assertArrayEquals("$rate Hz 分块", whole, parts.toFloatArray(), 0f)
        }
    }

    @Test
    fun chunkerProduces1600SampleChunks() {
        val chunks = ArrayList<ShortArray>()
        val c = PcmChunker(48_000).apply { onChunk = { chunks.add(it) } }
        val pcm = ShortArray(48_000) { (sin(2 * PI * 200 * it / 48_000) * 12_000).toInt().toShort() }
        var i = 0
        while (i < pcm.size) { c.feed(pcm.copyOfRange(i, minOf(i + 960, pcm.size))); i += 960 }
        assertEquals("1 s @48 kHz → 16000 采样 → 9 片满的（尾巴留在滤波器里）", 9, chunks.size)
        assertTrue(chunks.all { it.size == 1600 })
        assertEquals(32767, PcmChunker.toInt16(2f).toInt())
        assertEquals(-32768, PcmChunker.toInt16(-2f).toInt())
    }
}
