package joy.pinyintone.core.practice

import joy.pinyintone.core.json.jsonString
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * 一条声调记录（旧业务表 `training_sessions`）。字段与 iOS 上报的 `TrainingSessionDTO`
 * 一一对应（`SyncDTOs.swift`），[toDtoJson] 产出的键名与之相同，以后上传可以直接用。
 * `PracticeRecordTest` 解析那个 Swift 文件核对键名。
 */
data class TrainingRecord(
    val id: String,
    val deviceID: String,
    /** 学生不绑定班级，恒为 null（进入「未绑定班级」池，CLAUDE.md 禁令 4） */
    val classCode: String?,
    val role: String,
    /** 历史必填列，恒为 "n/a" */
    val groupAssignment: String,
    val lexemeID: String,
    /** 技术失败为 -1 哨兵 */
    val dtwScore: Double,
    /** FeedbackGrade 原始值；技术失败为 "n/a" */
    val grade: String,
    val attemptNumber: Int,
    /** 毫秒时间戳；上报时转 ISO8601（秒精度，与 iOS 相同） */
    val timestampMillis: Long,
    val referenceType: String?,
    val voicedFrameCount: Int,
    val qualityFlag: Boolean,
    val referenceSwitchedDuringAttempt: Boolean,
    val phase: String?,
    val wordSetID: String?,
    /** 历史字段，恒为 null */
    val presentationOrder: String?,
    val assessmentSetVersion: String?,
    /** 该条记录当时自选的显示模式；自测为 null。**禁止拿它做组间比较** */
    val feedbackMode: String?,
    val resultStatus: String?,
    val failureReason: String?,
    val schemaVersion: Int,
    val appVersion: String,
    val synced: Boolean = false,
) {
    /** 是否计入发音成绩（技术失败一律不计，CLAUDE.md 禁令 9）。通关以 grade 为准 */
    val passed: Boolean? get() = when {
        resultStatus == "technical_retry" -> null
        else -> grade != "fail"
    }

    fun toDtoJson(): String {
        fun s(v: String?) = v?.let(::jsonString) ?: "null"
        val ts = Instant.ofEpochMilli(timestampMillis).truncatedTo(ChronoUnit.SECONDS).toString()
        return listOf(
            "id" to s(id), "deviceID" to s(deviceID), "classCode" to s(classCode), "role" to s(role),
            "groupAssignment" to s(groupAssignment), "lexemeID" to s(lexemeID),
            "dtwScore" to dtwScore.toString(), "grade" to s(grade), "attemptNumber" to "$attemptNumber",
            "timestamp" to s(ts), "referenceType" to s(referenceType),
            "voicedFrameCount" to "$voicedFrameCount", "qualityFlag" to "$qualityFlag",
            "referenceSwitchedDuringAttempt" to "$referenceSwitchedDuringAttempt",
            "phase" to s(phase), "wordSetID" to s(wordSetID), "presentationOrder" to s(presentationOrder),
            "assessmentSetVersion" to s(assessmentSetVersion), "feedbackMode" to s(feedbackMode),
            "resultStatus" to s(resultStatus), "failureReason" to s(failureReason),
            "schemaVersion" to "$schemaVersion", "appVersion" to s(appVersion),
        ).joinToString(",", "{", "}") { (k, v) -> "${jsonString(k)}:$v" }
    }
}
