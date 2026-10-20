package joy.pinyintone.study

import joy.pinyintone.core.audio.AudioFramer
import joy.pinyintone.core.audio.F0Extractor
import joy.pinyintone.core.audio.ReferenceShaper
import joy.pinyintone.core.audio.ToneContour
import joy.pinyintone.core.audio.Wav
import java.io.File

/** 生产流程的薄封装（全部调用 :core 的正式实现） */
object Pipeline {
    val f0 = F0Extractor()
    val shaper = ReferenceShaper(f0)

    fun idealRef(tones: List<Int>): FloatArray = f0.normalize(ToneContour.ideal(tones))

    class Ref(val norm: FloatArray, val source: String)

    /** 与 App 相同的回退：TTS 整形失败 / 走向矛盾 → 理想轮廓 */
    fun ttsRef(samples: FloatArray, tones: List<Int>): Ref {
        val t = shaper.f0Track(samples, tones)
        return if (t.isEmpty()) Ref(idealRef(tones), "ideal(回退)") else Ref(t, "tts")
    }

    fun rawHz(samples: FloatArray): FloatArray {
        val frames = AudioFramer.frames(samples)
        return FloatArray(frames.size) { f0.extract(frames[it]) }
    }

    fun readWav(file: File): FloatArray = AudioFramer.floatSamples(Wav.readPcm16Mono16k(file))

    /** 学习者：clean → 有声帧检查 → normalize。null = 技术性重录 */
    class Learner(val cleaned: FloatArray, val norm: FloatArray)

    fun learner(raw: FloatArray): Learner? {
        val c = f0.clean(raw)
        if (c.count { it != 0f } < 5) return null
        return Learner(c, f0.normalize(c))
    }

    /** 纯 z-score（无下限），仅用于原因拆解的反事实 */
    fun normalizeNoFloor(track: FloatArray): FloatArray {
        val v = track.filter { it > 0 }
        val mean = v.map { it.toDouble() }.average()
        val sd = kotlin.math.sqrt(v.map { (it - mean) * (it - mean) }.average())
        return FloatArray(track.size) { if (track[it] > 0) ((track[it] - mean) / sd).toFloat() else 0f }
    }

    fun writeWav(file: File, samples: FloatArray) {
        val n = samples.size
        val bb = java.nio.ByteBuffer.allocate(44 + n * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        bb.put("RIFF".toByteArray()); bb.putInt(36 + n * 2); bb.put("WAVE".toByteArray())
        bb.put("fmt ".toByteArray()); bb.putInt(16); bb.putShort(1); bb.putShort(1)
        bb.putInt(16000); bb.putInt(32000); bb.putShort(2); bb.putShort(16)
        bb.put("data".toByteArray()); bb.putInt(n * 2)
        for (s in samples) bb.putShort((s.coerceIn(-1f, 0.99997f) * 32768).toInt().toShort())
        file.writeBytes(bb.array())
    }
}
