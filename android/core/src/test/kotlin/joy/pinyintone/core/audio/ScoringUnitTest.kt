package joy.pinyintone.core.audio

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.sin

/** 不依赖对照数据的单元测试：边界与不变式（对应 PinYintoneTests/Audio 里的同类断言）。 */
class ScoringUnitTest {

    private val f0 = F0Extractor()
    private val dtw = DTWAnalyzer()

    private fun sine(freq: Float, count: Int = 512) =
        FloatArray(count) { sin(2 * PI * freq * it / 16_000).toFloat() }

    @Test
    fun yinDetectsSine() {
        // 容差与 F0ExtractorTests.swift 相同（单帧 YIN 在高频处有几 Hz 的量化偏差）
        assertEquals(440f, f0.extract(sine(440f)), 10f)
        assertEquals(200f, f0.extract(sine(200f)), 8f)
        assertEquals(0f, f0.extract(FloatArray(512)))
        assertEquals(0f, f0.extract(sine(50f)))   // 低于 75 Hz 检测下限
    }

    @Test
    fun gradeBoundaries() {
        // CLAUDE.md：≤ 0.5 通关（含 0.5）
        assertEquals(FeedbackGrade.EXCELLENT, dtw.grade(0.1999f))
        assertEquals(FeedbackGrade.GOOD, dtw.grade(0.2f))
        assertEquals(FeedbackGrade.NEEDS_PRACTICE, dtw.grade(0.35f))
        assertEquals(FeedbackGrade.NEEDS_PRACTICE, dtw.grade(0.5f))
        assertEquals(FeedbackGrade.FAIL, dtw.grade(0.5000001f))
        assertEquals(FeedbackGrade.FAIL, dtw.grade(Float.NaN))
        assertTrue(dtw.passed(0.5f))
        assertFalse(dtw.passed(0.51f))
    }

    @Test
    fun dtwEmptySideIsMaxScore() {
        assertEquals(DTWAnalyzer.MAX_SCORE, dtw.distance(floatArrayOf(0f, 0f), floatArrayOf(1f)))
        assertEquals(0f, dtw.distance(floatArrayOf(1f, 2f), floatArrayOf(0f, 1f, 2f, 0f)))
    }

    @Test
    fun normalizeFloorKeepsLevelToneFlat() {
        // ±0.5 Hz 抖动的平调：纯 z-score 会放大成 ±1，带下限后应远小于 1
        val flat = FloatArray(40) { 265f + if (it % 2 == 0) 0.5f else -0.5f }
        val n = f0.normalize(flat)
        assertTrue(n.all { kotlin.math.abs(it) < 0.1f })
    }

    @Test
    fun gateOnlyForAllLevelTones() {
        val falling = FloatArray(30) { 270f - 3f * it }   // 约 -6 半音
        assertTrue(ToneDirectionGate.fails(falling, listOf(1, 1)))
        assertFalse(ToneDirectionGate.fails(falling, listOf(1, 4)))   // 禁令 16：不扩大
        assertFalse(ToneDirectionGate.fails(falling, emptyList()))
    }

    @Test
    fun technicalRetryHasNoScore() {
        val out = ToneScorer().evaluate(FloatArray(50), ToneScorer().idealReference(listOf(1)), listOf(1))
        assertTrue(out is ToneScorer.Outcome.TechnicalRetry)
        assertEquals("technical_retry", out.resultStatus.rawValue)
    }

    @Test
    fun framerChunkingMatchesWholeBuffer() {
        val pcm = ShortArray(5000) { (sin(it * 0.05) * 10000).toInt().toShort() }
        val viaFeed = ArrayList<FloatArray>()
        val framer = AudioFramer().apply { onFrame = { viaFeed.add(it) } }
        var i = 0
        while (i < pcm.size) { framer.feed(pcm.copyOfRange(i, minOf(i + 1600, pcm.size))); i += 1600 }
        val whole = AudioFramer.frames(AudioFramer.floatSamples(pcm))
        assertEquals(whole.size, viaFeed.size)
        whole.indices.forEach { assertArrayEquals(whole[it], viaFeed[it], 0f) }
    }
}
