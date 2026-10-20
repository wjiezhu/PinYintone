package joy.pinyintone.core.audio

import joy.pinyintone.core.json.Json
import joy.pinyintone.core.json.f
import joy.pinyintone.core.json.floats
import joy.pinyintone.core.json.i
import joy.pinyintone.core.json.ints
import joy.pinyintone.core.json.list
import joy.pinyintone.core.json.obj
import org.junit.AfterClass
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.max

/**
 * 与 Swift 版的对照测试。输入与期望值都来自仓库根目录的 `testdata/scoring/`
 * （由 iOS 测试 `PinYintoneTests/Golden/ScoringGoldenTests.swift` 生成）。
 *
 * 分两层比：
 * 1. **逐步**：把 Swift 的中间结果直接喂给对应的 Kotlin 函数，比单步输出。
 *    只用 Float 逐元素运算的步骤（clean、DTW、参照平滑、走向判定）必须**逐位一致**；
 *    用到 Accelerate 归约（normalize）或 libm（log2 / pow）的步骤只差最后几位。
 *    这一层抓的是「移植写错了」。
 * 2. **端到端**：Kotlin 从 WAV 起自己算到底，与 Swift 的最终结果比。
 *    YIN 差分函数的求和顺序不同（vDSP vs Double 累加），F0 带着 ~1e-6 的相对误差往下传。
 *    这一层抓的是「误差累积后会不会改变判定」。
 *
 * 判定类结果（有声/无声帧、技术重录、闸门、grade、是否通关、送气触发）一律要求**完全一致**。
 * 容差的取值理由见 android/README.md「对照测试与容差」。
 */
class ScoringGoldenTest {

    private val f0 = F0Extractor()
    private val dtw = DTWAnalyzer()
    private val scorer = ToneScorer(f0, dtw)
    private val shaper = ReferenceShaper(f0)

    // ---- 容差 ----
    /** 逐步比：Float 逐元素运算的步骤要求逐位一致 */
    private val exact = Tol(0.0, 0.0)
    /** 逐步比：经 Accelerate 归约 / libm 的步骤，几个 ulp（Float 的 ulp ≈ 6e-8 相对） */
    private val ulps = Tol(abs = 1e-5, rel = 1e-6)
    /** 端到端：F0（Hz）——0.01 Hz 级，远小于任何可听差别（1 音分 ≈ 0.06%） */
    private val hzE2E = Tol(abs = 1e-3, rel = 2e-5)
    /** 端到端：归一化值 / DTW 分数 / 半音 / dB 等无量纲量 */
    private val unitlessE2E = Tol(abs = 1e-4, rel = 1e-4)

    data class Tol(val abs: Double, val rel: Double)

    private fun check(label: String, expected: FloatArray, actual: FloatArray, tol: Tol) {
        assertEquals("$label 长度", expected.size, actual.size)
        var worst = 0.0
        for (k in expected.indices) {
            val e = expected[k].toDouble()
            val a = actual[k].toDouble()
            // 无声（0）与有声必须一一对应：0 帧在 DTW 里被丢弃，错一帧就会改变对齐
            assertEquals("$label[$k] 有声/无声不一致（期望 $e，实得 $a）", e == 0.0, a == 0.0)
            val d = abs(e - a)
            if (d > tol.abs + tol.rel * abs(e)) fail("$label[$k]：期望 $e，实得 $a，差 $d 超出容差 $tol")
            worst = max(worst, d)
        }
        record(label.substringAfter(" "), worst)
    }

    private fun check(label: String, expected: Float, actual: Float, tol: Tol) =
        check(label, floatArrayOf(expected), floatArrayOf(actual), tol)

    // ---- 数据 ----

    private val golden = Json.parse(File(dataDir, "golden.json").readText()).obj()

    private fun pcm(case: Map<String, Any?>): ShortArray =
        Wav.readPcm16Mono16k(File(dataDir, case["wav"] as String))

    // ---- 参数：两端锁定的常量必须相同（CLAUDE.md） ----

    @Test
    fun lockedParametersMatchSwift() {
        val p = golden["params"].obj()
        assertEquals(16_000, p["sampleRate"].i())
        assertEquals(F0Extractor.FRAME_SIZE, p["frameSize"].i())
        assertEquals(F0Extractor.HOP_SIZE, p["hopSize"].i())
        assertEquals(F0Extractor.MIN_F0, p["minF0"].f())
        assertEquals(F0Extractor.MAX_F0, p["maxF0"].f())
        assertEquals(F0Extractor.YIN_THRESHOLD, p["yinThreshold"].f())
        assertEquals(F0Extractor.NORMALIZATION_FLOOR_RATIO, p["normalizationFloorRatio"].f())
        assertEquals(DTWAnalyzer.PASS_THRESHOLD, p["passThreshold"].f())
        assertEquals(ToneDirectionGate.MAX_FALL_SEMITONES, p["gateMaxFallSemitones"].f())
        assertEquals(ToneScorer.MIN_VOICED_FRAMES, p["minVoicedFrames"].i())
        assertEquals(ToneContourSpanGate.MIN_SPAN_SEMITONES, p["contourGateMinSpanSemitones"].f())
        assertEquals(ToneContourSpanGate.MIN_VOICED_FRAMES, p["contourGateMinVoicedFrames"].i())
        assertEquals(ToneScorer.QUALITY_FLAG_THRESHOLD, p["qualityFlagThreshold"].f())
        assertEquals(AspirationDetector.CHUNK_SIZE, p["aspirationChunk"].i())
        assertEquals(AspirationDetector.CALIBRATION_CHUNKS, p["aspirationCalibrationChunks"].i())
        assertEquals(AspirationDetector.WINDOW_CHUNKS, p["aspirationWindowChunks"].i())
        assertEquals(AspirationDetector.PASS_TRIGGER_RATE, p["aspirationPassRate"].f())
    }

    @Test
    fun idealContours() {
        for ((key, v) in golden["toneContours"].obj()) {
            val c = v.obj()
            val ideal = ToneContour.ideal(c["tones"].ints())
            // pow / sin 走 Double 再转 Float，与 Apple 的 powf / sinf 至多差 1 ulp
            check("contour[$key] idealHz", c["idealHz"].floats(), ideal, ulps)
            check("contour[$key] normalized(swift idealHz)", c["normalized"].floats(),
                  f0.normalize(c["idealHz"].floats()), ulps)
            check("contour[$key] normalized(e2e)", c["normalized"].floats(), f0.normalize(ideal), unitlessE2E)
        }
    }

    @Test
    fun toneCasesStepwise() {
        for (raw in golden["toneCases"].list()) {
            val c = raw.obj()
            val name = c["name"] as String
            val tones = c["tones"].ints()
            val swiftRaw = c["f0Raw"].floats()
            val swiftClean = c["f0Clean"].floats()

            check("$name clean", swiftClean, f0.clean(swiftRaw), exact)
            check("$name referenceNormalized", c["referenceNormalized"].floats(),
                  f0.normalize(ToneContour.ideal(tones)), unitlessE2E)

            if (c["resultStatus"] != "technical_retry") {
                val swiftNorm = c["normalized"].floats()
                check("$name normalize", swiftNorm, f0.normalize(swiftClean), ulps)
                val ref = c["referenceNormalized"].floats()
                check("$name dtw", c["dtwScore"].f(), dtw.distance(ref, swiftNorm), exact)
                check("$name segmentScores", c["segmentScores"].floats(),
                      dtw.segmentScores(ref, swiftNorm, tones.size), exact)
                val gate = c["gate"].obj()
                val fall = ToneDirectionGate.fallSemitones(swiftClean, tones)
                if (gate["fallSemitones"] == null) assertNull("$name fallSemitones", fall)
                else check("$name gate.fallSemitones", gate["fallSemitones"].f(), fall!!, ulps)
                val cg = c["contourGate"].obj()
                assertEquals("$name contourGate.applies", cg["applies"], ToneContourSpanGate.applies(tones))
                val span = ToneContourSpanGate.spanSemitones(swiftClean)
                if (cg["spanSemitones"] == null) assertNull("$name spanSemitones", span)
                else check("$name contourGate.spanSemitones", cg["spanSemitones"].f(), span!!, ulps)
                assertEquals("$name contourGate.fails", cg["fails"], ToneContourSpanGate.fails(swiftClean, tones))
            }

            val s = c["referenceShaping"].obj()
            val smoothed = shaper.smoothReference(swiftClean)
            check("$name shaping.smoothed", s["smoothed"].floats(), smoothed, exact)
            // 两步都用到 ToneContour.ideal（pow），故允许几个 ulp
            check("$name shaping.deDeclined", s["deDeclined"].floats(),
                  shaper.removeExcessDeclination(s["smoothed"].floats(), tones), ulps)
            check("$name shaping.blended", s["blended"].floats(),
                  shaper.blendTowardIdeal(s["deDeclined"].floats(), tones), ulps)
            assertEquals("$name shaping.contradicts", s["contradicts"],
                         shaper.contourContradictsTones(s["blended"].floats(), tones))
        }
    }

    @Test
    fun toneCasesEndToEnd() {
        for (raw in golden["toneCases"].list()) {
            val c = raw.obj()
            val name = c["name"] as String
            val tones = c["tones"].ints()
            val pcm = pcm(c)

            // 与 App 一样按 1600 采样一片送进 AudioFramer
            val rawHz = ArrayList<Float>()
            val framer = AudioFramer().apply { onFrame = { rawHz.add(f0.extract(it)) } }
            var i = 0
            while (i < pcm.size) {
                framer.feed(pcm.copyOfRange(i, minOf(i + AspirationDetector.CHUNK_SIZE, pcm.size)))
                i += AspirationDetector.CHUNK_SIZE
            }
            val hz = rawHz.toFloatArray()
            check("$name f0Raw", c["f0Raw"].floats(), hz, hzE2E)

            val reference = scorer.idealReference(tones)
            val out = scorer.evaluate(hz, reference, tones)
            check("$name f0Clean(e2e)", c["f0Clean"].floats(), out.cleanedHz, hzE2E)
            assertEquals("$name voicedFrames", c["voicedFrames"].i(), out.voicedFrames)
            assertEquals("$name resultStatus", c["resultStatus"], out.resultStatus.rawValue)

            when (out) {
                is ToneScorer.Outcome.TechnicalRetry -> {
                    assertNull("$name 技术重录不应有分数", c["dtwScore"])
                    assertNull("$name 技术重录不应有等级", c["grade"])
                }
                is ToneScorer.Outcome.Scored -> {
                    check("$name normalized(e2e)", c["normalized"].floats(), out.normalized, unitlessE2E)
                    check("$name dtwScore(e2e)", c["dtwScore"].f(), out.dtwScore, unitlessE2E)
                    check("$name segmentScores(e2e)", c["segmentScores"].floats(), out.segmentScores, unitlessE2E)
                    val gate = c["gate"].obj()
                    assertEquals("$name gate.applies", gate["applies"], ToneDirectionGate.applies(tones))
                    assertEquals("$name gate.fails", gate["fails"], out.levelToneDropped)
                    gate["fallSemitones"]?.let {
                        check("$name gate.fallSemitones(e2e)", it.f(),
                              ToneDirectionGate.fallSemitones(out.cleanedHz, tones)!!, unitlessE2E)
                    }
                    val cg = c["contourGate"].obj()
                    assertEquals("$name contourGate.fails(e2e)", cg["fails"], out.flatContour)
                    if (cg["spanSemitones"] == null) assertNull("$name span(e2e)", out.pitchSpanSemitones)
                    else check("$name contourGate.spanSemitones(e2e)", cg["spanSemitones"].f(),
                               out.pitchSpanSemitones!!, unitlessE2E)
                    assertEquals("$name grade", c["grade"], out.grade.rawValue)
                    assertEquals("$name passed", c["passed"], out.passed)
                }
            }

            val s = c["referenceShaping"].obj()
            val samples = AudioFramer.floatSamples(pcm)
            check("$name trackWithTones(e2e)", s["trackWithTones"].floats(), shaper.f0Track(samples, tones), unitlessE2E)
            check("$name trackWithoutTones(e2e)", s["trackWithoutTones"].floats(),
                  shaper.f0Track(samples, emptyList()), unitlessE2E)
        }
    }

    @Test
    fun aspirationCases() {
        for (raw in golden["aspirationCases"].list()) {
            val c = raw.obj()
            val name = c["name"] as String
            val pcm = pcm(c)
            val chunk = AspirationDetector.CHUNK_SIZE
            val chunks = (0 until pcm.size / chunk).map {
                AudioFramer.floatSamples(pcm.copyOfRange(it * chunk, (it + 1) * chunk))
            }
            val det = AspirationDetector()
            det.calibrateBaseline(chunks.take(AspirationDetector.CALIBRATION_CHUNKS))
            check("$name baselineDB", c["baselineDB"].f(), det.baselineDB, unitlessE2E)
            check("$name thresholdDB", c["thresholdDB"].f(), det.thresholdDB, unitlessE2E)

            val window = ArrayDeque<FloatArray>()
            val detects = ArrayList<Boolean>()
            val rates = ArrayList<Float>()
            var passedAt: Int? = null
            chunks.drop(AspirationDetector.CALIBRATION_CHUNKS).forEachIndexed { k, frame ->
                window.addLast(frame)
                if (window.size > AspirationDetector.WINDOW_CHUNKS) window.removeFirst()
                val rate = det.triggerRate(window.toList())
                rates.add(rate)
                detects.add(det.detect(frame))
                if (rate >= AspirationDetector.PASS_TRIGGER_RATE && passedAt == null) passedAt = k
            }
            assertEquals("$name detect", c["detect"].list(), detects)
            // 触发率是 k/n 的分数，判定一致则逐位一致
            assertArrayEquals("$name triggerRate", c["triggerRate"].floats(), rates.toFloatArray(), 0f)
            assertEquals("$name passedAtChunk", c["passedAtChunk"]?.i(), passedAt)
        }
    }

    @Test
    fun goldenCoversRequiredScenarios() {
        val cases = golden["toneCases"].list().map { it.obj() }
        // 必须同时有：通关 / 不通关 / 闸门拦下（DTW 本身在线内）/ 技术重录 / 参照整形判矛盾
        assertTrue(cases.any { it["passed"] == true })
        assertTrue(cases.any { it["passed"] == false })
        assertTrue("至少一例被闸门拦下", cases.any { it["gate"]?.obj()?.get("fails") == true })
        assertTrue(cases.any { it["resultStatus"] == "technical_retry" })
        assertTrue(cases.any { it["referenceShaping"].obj()["contradicts"] == true })
        val asp = golden["aspirationCases"].list().map { it.obj() }
        assertTrue(asp.any { it["passedAtChunk"] != null })
        assertTrue(asp.any { it["passedAtChunk"] == null })
    }

    companion object {
        private val dataDir = File(
            System.getProperty("pinyintone.scoringTestdata") ?: "../../testdata/scoring",
        )

        /** 每类比较的最大实际误差，测试结束写进 build/reports/golden-diff.txt，供定容差参考 */
        private val worst = sortedMapOf<String, Double>()

        @Synchronized
        private fun record(kind: String, d: Double) {
            worst[kind] = max(worst[kind] ?: 0.0, d)
        }

        @AfterClass
        @JvmStatic
        fun writeReport() {
            val f = File("build/reports/golden-diff.txt")
            f.parentFile.mkdirs()
            f.writeText(worst.entries.joinToString("\n") { "${it.key}\t${it.value}" } + "\n")
        }
    }
}
