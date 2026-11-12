package joy.pinyintone.core.practice

/**
 * 记录版本与取值，对应 Swift `RecordSchema.swift` / `TrainingPhase.swift` / `FeedbackStyle.swift`。
 * 语义与 iOS **完全相同**——两端的记录进同一张表，同一个 `schemaVersion` 必须是同一个意思。
 */
object RecordSchema {
    /** 记录字段版本。与 iOS 同步：字段增删或语义变更时两端一起 +1（见 Swift 注释里的版本史） */
    const val VERSION = 8

    /** 记录来自哪一端（v8 起上报）。iOS 写 "ios" */
    const val PLATFORM = "android"
}

/** 技术失败记录的占位值。**绝不写 0**（会被读成满分），也不写 `fail`（那是发音判定） */
object RecordSentinel {
    const val NO_SCORE: Double = -1.0
    const val NO_GRADE: String = "n/a"
}

/** 旧业务表 `phase`。新版只写 TRAINING / SELF_TEST；pretest / posttest 只存在于历史记录 */
enum class TrainingPhase(val rawValue: String) {
    TRAINING("training"),
    SELF_TEST("self_test"),
}

/** 技术失败原因（匿名，不含任何录音内容） */
enum class FailureReason(val rawValue: String) {
    INSUFFICIENT_VOICED_FRAMES("insufficient_voiced_frames"),
    PERMISSION_DENIED("permission_denied"),
    RECORDING_INTERRUPTED("recording_interrupted"),
    LOW_SIGNAL_QUALITY("low_signal_quality"),
    ANALYSIS_ERROR("analysis_error"),
}

/** 参照来源：真人录音 > TTS > 理想轮廓。Android **不用系统 TTS 生成评分参照**（各厂商语音不同） */
enum class ReferenceType(val rawValue: String) {
    REAL("real"),
    TTS("tts"),
    IDEAL("ideal"),
}

/**
 * 反馈显示模式：学习者自选的**显示偏好**，不是实验条件（CLAUDE.md 禁令 2 / 10）。
 * 两种模式通关标准完全一致；默认动态曲线。
 */
enum class FeedbackStyle(val rawValue: String) {
    DYNAMIC_F0("dynamicF0"),
    STATIC_COLOR("staticColor");

    val localizationKey: String get() = "condition_$rawValue"

    companion object {
        val DEFAULT = DYNAMIC_F0
        fun of(raw: String?): FeedbackStyle = entries.firstOrNull { it.rawValue == raw } ?: DEFAULT
    }
}

/** 自测词集版本，随自测记录上报（与 iOS `AssessmentSet.version` 相同） */
const val ASSESSMENT_SET_VERSION = "assess-v1"
