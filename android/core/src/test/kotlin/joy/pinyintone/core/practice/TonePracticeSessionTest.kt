package joy.pinyintone.core.practice

import joy.pinyintone.core.RepoFiles
import joy.pinyintone.core.audio.ToneScorer
import joy.pinyintone.core.audio.ToneContour
import joy.pinyintone.core.corpus.Corpus
import joy.pinyintone.core.practice.TonePracticeSession.Failure
import joy.pinyintone.core.practice.TonePracticeSession.Mode
import joy.pinyintone.core.practice.TonePracticeSession.Stage
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class TonePracticeSessionTest {

    private class MemStore : PracticeStore {
        val counts = HashMap<String, Int>()
        override fun attempts(lexemeID: String) = counts[lexemeID] ?: 0
        override fun incrementAttempts(lexemeID: String) = (attempts(lexemeID) + 1).also { counts[lexemeID] = it }
        override var practiceCursor = 0
    }

    private val corpus = Corpus.parse(RepoFiles.read("PinYintone/Resources/Corpus/lexemes.json"))
    private val store = MemStore()
    private val records = ArrayList<TrainingRecord>()
    private var ids = 0
    private val session = TonePracticeSession(
        corpus, store, { records.add(it) }, RecordContext("dev-1", "0.1.0 (1)"),
        clock = { 1_700_000_000_000 }, newID = { "id-${ids++}" },
    ).apply { loadCurrent() }

    /** 按目标声调的理想轮廓「读」：每音节 40 帧 Hz，音节间 6 帧无声 */
    private fun read(tones: List<Int>, transform: (Float) -> Float = { it }): FloatArray {
        val out = ArrayList<Float>()
        for (t in tones) {
            ToneContour.ideal(listOf(t), perSyllable = 40).forEach { out.add(transform(it)) }
            repeat(6) { out.add(0f) }
        }
        return out.toFloatArray()
    }

    private fun recordOnce(hz: FloatArray, style: FeedbackStyle = FeedbackStyle.DYNAMIC_F0) {
        assertTrue(session.beginRecording())
        // 录音线程每 0.1 s 送一批（12–13 帧）
        hz.toList().chunked(12).forEach { session.onF0Frames(it.toFloatArray()) }
        session.stopAndEvaluate(style)
    }

    @Test
    fun startsOnFirstWordWithIdealReference() {
        assertEquals("yisheng", session.lexeme?.id)
        assertEquals(Stage.Ready, session.stage)
        assertEquals(ReferenceType.IDEAL, session.referenceType)
        assertArrayEquals(ToneScorer().idealReference(listOf(1, 1)), session.reference, 0f)
        assertEquals(1 to 14, session.progress)
    }

    @Test
    fun validAttemptWritesRecordAlignedWithIos() {
        recordOnce(read(listOf(1, 1)))
        assertEquals(Stage.Feedback, session.stage)
        val fb = session.feedback!!
        assertTrue(fb.passed)
        val r = records.single()
        assertEquals("yisheng", r.lexemeID)
        assertEquals(fb.dtwScore.toDouble(), r.dtwScore, 0.0)
        assertEquals(fb.grade, r.grade)
        assertEquals(1, r.attemptNumber)
        assertEquals("training", r.phase)
        assertEquals("set1", r.wordSetID)
        assertNull(r.assessmentSetVersion)
        assertEquals("dynamicF0", r.feedbackMode)
        assertEquals("ideal", r.referenceType)
        assertEquals("valid_result", r.resultStatus)
        assertNull(r.failureReason)
        assertNull(r.classCode)
        assertEquals("n/a", r.groupAssignment)
        assertNull(r.presentationOrder)
        assertEquals(RecordSchema.VERSION, r.schemaVersion)
        assertFalse(r.synced)
        assertTrue(session.learnerCurve.isNotEmpty())

        // 换显示模式不影响评分，只影响记录里的 feedbackMode
        session.clearFeedbackForRetry()
        recordOnce(read(listOf(1, 1)), FeedbackStyle.STATIC_COLOR)
        assertEquals(records[0].dtwScore, records[1].dtwScore, 0.0)
        assertEquals("staticColor", records[1].feedbackMode)
        assertEquals(2, records[1].attemptNumber)
    }

    @Test
    fun technicalRetryUsesSentinelsAndDoesNotCountAsAttempt() {
        recordOnce(FloatArray(40))   // 全是无声帧
        assertEquals(Stage.Failed(Failure.NO_VOICE), session.stage)
        assertNull(session.feedback)
        val r = records.single()
        assertEquals(-1.0, r.dtwScore, 0.0)       // 哨兵不写 0
        assertEquals("n/a", r.grade)               // 不写 fail
        assertEquals("technical_retry", r.resultStatus)
        assertEquals("insufficient_voiced_frames", r.failureReason)
        assertNull(r.feedbackMode)
        assertNull(r.passed)
        assertEquals(0, r.attemptNumber)
        assertEquals(0, store.attempts("yisheng"))
        // 失败后可以直接再录
        assertTrue(session.canRecord)
    }

    @Test
    fun levelToneGateDecidesPassEvenWhenDtwIsWithinThreshold() {
        // 一声词一路下滑约 5 个半音：形状像理想 T1，DTW 可能在线内，但闸门拦下
        val falling = FloatArray(80) { 270f - 70f * it / 79f }
        recordOnce(falling)
        val fb = session.feedback!!
        assertTrue(fb.levelToneDropped)
        assertEquals("fail", fb.grade)
        assertFalse(fb.passed)
        assertTrue("闸门拦下的分数不高于 59", fb.score <= 59)
        assertEquals("fail", records.single().grade)
        assertEquals(1, session.consecutiveFailures)
    }

    @Test
    fun flatReadingOfContourWordIsGatedAndSpanIsRecorded() {
        session.select("xianzai")   // 现在 4+4
        recordOnce(FloatArray(90) { 220f - 2f * it / 89f })   // 读平，带一点点下倾
        val fb = session.feedback!!
        assertTrue(fb.flatContour)
        assertFalse(fb.levelToneDropped)
        assertEquals("fail", fb.grade)
        assertTrue("闸门拦下的分数不高于 59", fb.score <= 59)
        val r = records.single()
        assertEquals("fail", r.grade)
        assertTrue(r.pitchSpanSemitones!! < 2.0)
        assertEquals("android", r.platform)
        assertEquals(8, r.schemaVersion)
    }

    @Test
    fun correctReadingPassesContourGateAndRecordsSpan() {
        session.select("xianzai")
        recordOnce(read(listOf(4, 4)))
        val fb = session.feedback!!
        assertFalse(fb.flatContour)
        assertTrue(fb.passed)
        assertTrue(records.single().pitchSpanSemitones!! > 4.0)
    }

    @Test
    fun technicalRetryHasNoSpan() {
        session.select("xianzai")
        recordOnce(FloatArray(40))
        assertNull(records.single().pitchSpanSemitones)
        assertEquals("android", records.single().platform)
    }

    @Test
    fun permissionAndDeviceFailuresAreNeverSilent() {
        session.onPermissionDenied()
        assertEquals(Stage.Failed(Failure.MICROPHONE_DENIED), session.stage)
        assertTrue(session.failure!!.offersSettings)
        assertEquals("permission_denied", records.last().failureReason)
        session.onPermissionGranted()
        assertEquals(Stage.Ready, session.stage)

        assertTrue(session.beginRecording())
        session.onRecordingStartFailed(permissionDenied = false)
        assertEquals(Stage.Failed(Failure.MICROPHONE_UNAVAILABLE), session.stage)
        assertEquals("technical_retry", records.last().resultStatus)

        assertTrue(session.beginRecording())
        session.onInterrupted()
        assertEquals(Stage.Failed(Failure.INTERRUPTED), session.stage)
        assertEquals("recording_interrupted", records.last().failureReason)
        assertEquals(3, records.size)
        assertTrue(records.all { it.dtwScore == -1.0 && it.attemptNumber == 0 })
    }

    @Test
    fun cancelLeavesNoRecord() {
        assertTrue(session.beginRecording())
        session.onF0Frames(read(listOf(1, 1)))
        session.cancelRecording()
        assertEquals(Stage.Ready, session.stage)
        assertTrue(records.isEmpty())
    }

    @Test
    fun cannotSwitchWordWhileBusy() {
        assertTrue(session.beginRecording())
        session.loadNext()
        session.select("hanzi")
        session.beginSelfTest()
        assertEquals("yisheng", session.lexeme?.id)
        assertEquals(Mode.PRACTICE, session.mode)
    }

    @Test
    fun wordNavigationWrapsAndPersistsCursor() {
        session.select("hanzi")
        assertEquals("hanzi", session.lexeme?.id)
        assertEquals(13, store.practiceCursor)
        session.loadNext()
        assertEquals("yisheng", session.lexeme?.id)
        session.select("not-a-word")
        assertEquals("yisheng", session.lexeme?.id)
    }

    @Test
    fun selfTestScoresInBackgroundButExposesNoFeedback() {
        store.counts["xiangxin"] = 2
        session.beginSelfTest()
        assertEquals(Mode.SELF_TEST, session.mode)
        assertEquals("xiangxin", session.lexeme?.id)
        assertEquals(1, session.selfTest!!.position)
        assertEquals(4, session.selfTest!!.total)

        session.beginRecording()
        session.onF0Frames(read(listOf(1, 4)))
        session.refreshLiveCurve()
        assertTrue("自测录音中不画曲线", session.learnerCurve.isEmpty())
        session.stopAndEvaluate(FeedbackStyle.DYNAMIC_F0)

        assertEquals(Stage.SelfTestRecorded, session.stage)
        assertNull("自测不生成可呈现的反馈", session.feedback)
        assertTrue(session.learnerCurve.isEmpty())
        val r = records.single()
        assertEquals("self_test", r.phase)
        assertNull("自测没有显示模式", r.feedbackMode)
        assertEquals(ASSESSMENT_SET_VERSION, r.assessmentSetVersion)
        assertEquals(3, r.attemptNumber)
        assertTrue(r.dtwScore >= 0)

        // 技术失败不推进这一题
        session.advanceSelfTest()
        assertEquals("heshui", session.lexeme?.id)
        recordOnce(FloatArray(30))
        assertEquals(Stage.Failed(Failure.NO_VOICE), session.stage)
        session.advanceSelfTest()
        assertEquals("heshui", session.lexeme?.id)

        // 走完
        for (tones in listOf(listOf(1, 3), listOf(4, 4), listOf(4, 4))) {
            recordOnce(read(tones)); session.advanceSelfTest()
        }
        assertTrue(session.selfTestFinished)
        assertFalse(session.canRecord)

        session.endSelfTest()
        assertEquals(Mode.PRACTICE, session.mode)
        assertEquals("yisheng", session.lexeme?.id)
        assertNull(session.selfTest)
    }

    @Test
    fun cancellingSelfTestMidRecordingReturnsToPractice() {
        session.beginSelfTest()
        session.beginRecording()
        session.endSelfTest()
        assertEquals(Mode.PRACTICE, session.mode)
        assertEquals(Stage.Ready, session.stage)
        assertTrue(records.isEmpty())
    }

    @Test
    fun realReferenceArrivingDuringRecordingIsAppliedAfterwards() {
        val withAudio = Corpus(corpus.lexemes.map { if (it.id == "yisheng") it.copy(audioFilename = "yisheng.wav") else it })
        val s = TonePracticeSession(withAudio, MemStore(), { records.add(it) }, RecordContext("d", "v"))
        s.loadCurrent()
        assertEquals(Stage.Preparing, s.stage)
        assertEquals("yisheng.wav", s.pendingReferenceFile)
        assertFalse("参照未就绪不能录", s.beginRecording())

        // 提取失败 → 保持理想轮廓，可以录
        s.applyReference("yisheng", FloatArray(0), ReferenceType.REAL)
        assertEquals(Stage.Ready, s.stage)
        assertEquals(ReferenceType.IDEAL, s.referenceType)

        val ideal = s.reference
        val real = FloatArray(60) { if (it % 2 == 0) 0.1f else -0.1f }
        assertTrue(s.beginRecording())
        s.applyReference("yisheng", real, ReferenceType.REAL)
        assertArrayEquals("录音中参照不变", ideal, s.displayReference, 0f)
        s.onF0Frames(read(listOf(1, 1)))
        s.stopAndEvaluate(FeedbackStyle.DYNAMIC_F0)
        assertEquals("这次用的是锁定的理想参照", "ideal", records.last().referenceType)
        assertArrayEquals(real, s.reference, 0f)
        assertEquals(ReferenceType.REAL, s.referenceType)
    }

    @Test
    fun skipHintAfterRepeatedFailures() {
        session.select("xianzai")   // 4+4
        repeat(3) {
            recordOnce(read(listOf(2, 2)))
            assertNotNull(session.feedback)
            session.clearFeedbackForRetry()
        }
        assertEquals(TonePracticeSession.SKIP_HINT_THRESHOLD, session.consecutiveFailures)
        session.loadNext()
        assertEquals(0, session.consecutiveFailures)
    }
}
