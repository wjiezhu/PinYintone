package joy.pinyintone.core.practice

import joy.pinyintone.core.RepoFiles
import joy.pinyintone.core.json.Json
import joy.pinyintone.core.json.obj
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PracticeRecordTest {

    private val record = TrainingRecord(
        id = "a", deviceID = "d", classCode = null, role = "student", groupAssignment = "n/a",
        lexemeID = "yisheng", dtwScore = -1.0, grade = "n/a", attemptNumber = 0,
        timestampMillis = 1_700_000_000_123, referenceType = null, voicedFrameCount = 2,
        qualityFlag = false, referenceSwitchedDuringAttempt = false, phase = "training",
        wordSetID = "set1", presentationOrder = null, assessmentSetVersion = null, feedbackMode = null,
        resultStatus = "technical_retry", failureReason = "insufficient_voiced_frames",
        schemaVersion = RecordSchema.VERSION, appVersion = "0.1.0 (1)",
    )

    /** 上报字段与 iOS `TrainingSessionDTO` 的键逐个相同、顺序相同 */
    @Test
    fun dtoKeysMatchIos() {
        val swift = RepoFiles.read("PinYintone/Core/Network/SyncDTOs.swift")
        val body = Regex("""struct TrainingSessionDTO: Codable \{(.*?)\n}""", RegexOption.DOT_MATCHES_ALL)
            .find(swift)!!.groupValues[1]
        val iosKeys = Regex("""let (\w+):""").findAll(body).map { it.groupValues[1] }.toList()
        val ours = Json.parse(record.toDtoJson()).obj().keys.toList()
        assertEquals(iosKeys, ours)
    }

    @Test
    fun dtoValues() {
        val o = Json.parse(record.toDtoJson()).obj()
        assertEquals("2023-11-14T22:13:20Z", o["timestamp"])
        assertEquals(null, o["classCode"])
        assertEquals("-1.0", (o["dtwScore"] as Json.Num).raw)
        assertEquals(false, o["qualityFlag"])
    }

    @Test
    fun schemaVersionMatchesIos() {
        val swift = RepoFiles.read("PinYintone/Core/Experiment/RecordSchema.swift")
        val v = Regex("""static let version = (\d+)""").find(swift)!!.groupValues[1].toInt()
        assertEquals(v, RecordSchema.VERSION)
        val sentinels = RepoFiles.read("PinYintone/Core/Experiment/RecordSchema.swift")
        assertTrue(sentinels.contains("static let noScore: Double = -1"))
        assertTrue(sentinels.contains("static let noGrade = \"n/a\""))
    }

    @Test
    fun feedbackScoreMatchesIosMapping() {
        // 与 FeedbackScoreTests.swift 相同的断言
        assertEquals(100, FeedbackScore.of(0f, false))
        assertEquals(0, FeedbackScore.of(1f, false))
        assertEquals(0, FeedbackScore.of(2f, false))
        assertEquals(90, FeedbackScore.of(0.2f, false))
        assertEquals(75, FeedbackScore.of(0.35f, false))
        assertEquals(60, FeedbackScore.of(0.5f, false))
        assertTrue(FeedbackScore.of(0.49f, false) >= 60)
        assertTrue(FeedbackScore.of(0.51f, false) < 60)
        var last = 101
        var d = 0f
        while (d <= 1.2f) {
            val s = FeedbackScore.of(d, false)
            assertTrue(s in 0..last)
            last = s
            d += 0.01f
        }
        assertEquals(59, FeedbackScore.of(0.1f, true))
    }

    @Test
    fun chartDropsUnvoicedFramesAndSharesTheTimeAxis() {
        val c = ChartGeometry.curves(
            floatArrayOf(0f, 1f, 2f, 3f, 0f),
            floatArrayOf(0f, -9f, Float.NaN, 0f, 9f),
        )
        assertEquals(3, c.reference.size)
        assertEquals(2, c.learner.size)
        // 共用分母（较长者 3 点 → 2）：学习者的线短，不拉伸铺满
        assertEquals(1f, c.reference.last().first)
        assertEquals(0.5f, c.learner.last().first)
        // 超出 ±2.5 夹住
        assertEquals(1f, c.learner.first().second)
        assertEquals(0f, c.learner.last().second)
        assertTrue(ChartGeometry.curves(FloatArray(3), floatArrayOf(1f)).isEmpty)
    }
}
