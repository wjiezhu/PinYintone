package joy.pinyintone.core.audio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.pow

/** 与 Swift `ToneContourSpanGateTests` 同一组断言 */
class ToneContourSpanGateTest {

    private fun ramp(startHz: Float, semitones: Float, n: Int = 48) =
        FloatArray(n) { (startHz * 2.0.pow(semitones.toDouble() * it / (n - 1) / 12)).toFloat() }

    @Test
    fun appliesOnlyToWordsWithTone234AndNeverOverlapsLevelGate() {
        assertTrue(ToneContourSpanGate.applies(listOf(4, 4)))
        assertTrue(ToneContourSpanGate.applies(listOf(1, 3)))
        assertTrue(ToneContourSpanGate.applies(listOf(4, 5)))
        assertFalse(ToneContourSpanGate.applies(listOf(1, 1)))
        assertFalse(ToneContourSpanGate.applies(listOf(1, 5)))
        assertFalse(ToneContourSpanGate.applies(emptyList()))
        for (t in listOf(listOf(1, 1), listOf(1), listOf(1, 5), listOf(4, 4), listOf(2, 3), listOf(1, 4))) {
            assertFalse("$t", ToneContourSpanGate.applies(t) && ToneDirectionGate.applies(t))
        }
    }

    @Test
    fun spanIsRegisterAndDurationIndependent() {
        val male = ToneContourSpanGate.spanSemitones(ramp(120f, -8f))!!
        val female = ToneContourSpanGate.spanSemitones(ramp(260f, -8f))!!
        assertEquals(male, female, 1e-3f)
        assertEquals(6.4f, male, 0.2f)
        val short = ToneContourSpanGate.spanSemitones(ramp(200f, 5f, 24))!!
        val long = ToneContourSpanGate.spanSemitones(floatArrayOf(0f, 0f) + ramp(200f, 5f, 120) + floatArrayOf(0f))!!
        assertEquals(short, long, 0.15f)
    }

    @Test
    fun tooFewVoicedFramesGivesNullAndNoGate() {
        assertNull(ToneContourSpanGate.spanSemitones(floatArrayOf(0f, 200f, 210f, 0f, 220f, 230f, 240f)))
        assertNotNull(ToneContourSpanGate.spanSemitones(floatArrayOf(200f, 210f, 220f, 230f, 240f, 250f)))
        assertFalse(ToneContourSpanGate.fails(floatArrayOf(220f, 220f, 220f, 0f, 0f), listOf(4, 4)))
    }

    @Test
    fun octaveSpikesDoNotInflateSpan() {
        val flat = FloatArray(60) { 220f }.also { it[10] = 440f; it[30] = 110f }
        assertTrue(ToneContourSpanGate.spanSemitones(flat)!! < 0.01f)
    }

    @Test
    fun flatFailsRealContoursPass() {
        assertTrue(ToneContourSpanGate.fails(ramp(220f, -1f), listOf(4, 4)))
        assertTrue(ToneContourSpanGate.fails(ramp(220f, 0f), listOf(2, 4)))
        for (t in listOf(listOf(4, 4), listOf(2, 2), listOf(3, 1), listOf(3, 2), listOf(2, 1), listOf(4, 5),
                         listOf(1, 4), listOf(3, 4))) {
            assertFalse("$t", ToneContourSpanGate.fails(ToneContour.ideal(t), t))
        }
        assertFalse(ToneContourSpanGate.fails(ramp(220f, -3.6f), listOf(4, 4)))
        assertFalse(ToneContourSpanGate.fails(ramp(266f, 0f), listOf(1, 1)))
        assertFalse(ToneContourSpanGate.fails(ramp(266f, 0f), listOf(1, 5)))
    }
}
