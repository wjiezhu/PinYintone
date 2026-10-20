package joy.pinyintone.core.practice

import joy.pinyintone.core.audio.F0Extractor
import joy.pinyintone.core.audio.ToneScorer
import joy.pinyintone.core.corpus.Corpus
import joy.pinyintone.core.corpus.LexemeCategory
import joy.pinyintone.core.corpus.Lexeme
import java.util.UUID

/** 本机持久化的练习状态（app 用 SharedPreferences 实现；测试用内存实现） */
interface PracticeStore {
    /** 该词此前有效录完的次数。对应 Swift `ToneAttemptStore` */
    fun attempts(lexemeID: String): Int
    /** 自增并返回本次的尝试序号（1-based） */
    fun incrementAttempts(lexemeID: String): Int
    /** 普通练习停留的位置。对应 `pt_tone_practice_cursor` */
    var practiceCursor: Int
}

/** 记录落库（app 用 Room 实现） */
fun interface RecordSink {
    fun save(record: TrainingRecord)
}

/** 写进每条记录的设备与版本信息 */
data class RecordContext(
    val deviceID: String,
    val appVersion: String,
    val role: String = "student",
)

/**
 * 声调练习的状态机与记录逻辑（平台无关部分）。
 * 对应 Swift `ToneTrainingViewModel` 里除界面、录音设备、研究日志之外的部分。
 *
 * 两种用法（CLAUDE.md「普通练习与可选自测」）：
 * - **普通练习**（默认）：有反馈，可选词、换词、重录，随时退出。没有任何前置门槛。
 * - **自测**（学习者主动开始）：只推进录音，不产生任何可呈现的反馈（分数、等级、曲线），
 *   后台照常算分入库；可随时取消，取消与完成都回到普通练习。
 * 两者用同一套评分（[ToneScorer]），差别只在呈现。
 *
 * 单线程使用（app 在主线程调用）。录音线程算出的 F0 用 [onF0Frames] 送进来。
 */
class TonePracticeSession(
    private val corpus: Corpus,
    private val store: PracticeStore,
    private val sink: RecordSink,
    private val context: RecordContext,
    private val clock: () -> Long = System::currentTimeMillis,
    private val newID: () -> String = { UUID.randomUUID().toString() },
) {
    sealed class Stage {
        /** 正在准备参考曲线，不能录音 */
        object Preparing : Stage()
        object Ready : Stage()
        object Recording : Stage()
        object Analyzing : Stage()
        /** 有效结果已出（只在普通练习） */
        object Feedback : Stage()
        /** 自测：这一词已录到，稍后自动进入下一词 */
        object SelfTestRecorded : Stage()
        /** 技术原因没成，可恢复。**不是低分**，也没有成绩 */
        data class Failed(val failure: Failure) : Stage()

        override fun toString(): String = javaClass.simpleName
    }

    /** 技术失败的种类。每种对应一句「下一步怎么做」（键名与 iOS 相同） */
    enum class Failure(val messageKey: String, val offersSettings: Boolean = false) {
        MICROPHONE_DENIED("tone_fail_mic_denied", offersSettings = true),
        MICROPHONE_UNAVAILABLE("tone_retry_mic_unavailable"),
        NO_VOICE("tone_retry_no_voice"),
        INTERRUPTED("tone_fail_interrupted"),
        ANALYSIS("tone_fail_analysis"),
    }

    enum class Mode { PRACTICE, SELF_TEST }

    /** 普通练习一次有效结果（自测从不生成这个对象，界面无从显示） */
    data class Feedback(
        val dtwScore: Float,
        val grade: String,
        val levelToneDropped: Boolean,
        /** 0–100 显示分（形成性反馈，不是能力等级） */
        val score: Int,
    ) {
        /** 通关以 grade 为准（闸门拦下时 dtwScore 可能 ≤ 0.5 仍不通关） */
        val passed: Boolean get() = grade != "fail"
    }

    data class SelfTestProgress(val words: List<String>, val index: Int = 0) {
        val total: Int get() = words.size
        /** 1-based，用于「第 x / n 词」 */
        val position: Int get() = minOf(index + 1, maxOf(total, 1))
        val currentID: String? get() = words.getOrNull(index)
        val isFinished: Boolean get() = index >= words.size
    }

    // ---- 可见状态 ----
    var stage: Stage = Stage.Preparing; private set
    var mode: Mode = Mode.PRACTICE; private set
    var lexeme: Lexeme? = null; private set
    /** 当前参照（归一化）。录音中显示用 [displayReference] */
    var reference: FloatArray = FloatArray(0); private set
    var referenceType: ReferenceType = ReferenceType.IDEAL; private set
    /** 学习者曲线（归一化）。自测里恒为空——自测不画任何曲线 */
    var learnerCurve: FloatArray = FloatArray(0); private set
    var feedback: Feedback? = null; private set
    /** 当前词连续未通过次数；达到 [SKIP_HINT_THRESHOLD] 提示可以先换一个词 */
    var consecutiveFailures: Int = 0; private set
    var selfTest: SelfTestProgress? = null; private set
    var selfTestFinished: Boolean = false; private set
    /** 当前词有母语者录音、需要 app 异步提取参照时为该文件名；提取完调 [applyReference] */
    var pendingReferenceFile: String? = null; private set

    /** 每次状态变化后回调（app 据此刷新界面） */
    var onChange: (() -> Unit)? = null

    val isRecording: Boolean get() = stage == Stage.Recording
    /** 录音、分析期间不能切词、切模式或播放 */
    val isBusy: Boolean get() = stage == Stage.Recording || stage == Stage.Analyzing
    val canRecord: Boolean get() = when (stage) {
        Stage.Ready, Stage.Feedback, Stage.Recording, is Stage.Failed -> !selfTestFinished
        else -> false
    }
    val failure: Failure? get() = (stage as? Stage.Failed)?.failure
    /** 录音中显示锁定的参照：看到的线 = 评分的线 */
    val displayReference: FloatArray get() = if (isRecording) lockedReference else reference
    val progress: Pair<Int, Int> get() {
        val pool = practicePool
        if (pool.isEmpty()) return 0 to 0
        return (normalizedCursor(pool.size) + 1) to pool.size
    }
    val practicePool: List<Lexeme> get() = corpus.orderedPool(LexemeCategory.TONE)

    // ---- 内部 ----
    private val f0 = F0Extractor()
    private val scorer = ToneScorer(f0)
    private var accumulated = FloatArray(1024)
    private var accumulatedCount = 0
    private var lockedReference = FloatArray(0)
    private var lockedReferenceType = ReferenceType.IDEAL
    private var pendingReference: Pair<FloatArray, ReferenceType>? = null
    private var referenceReady = false

    // ================= 选词 =================

    /** 进入练习页：载入上次停留的词 */
    fun loadCurrent() {
        if (mode != Mode.PRACTICE) return
        val pool = practicePool
        if (pool.isEmpty()) { lexeme = null; changed(); return }
        loadLexeme(pool[normalizedCursor(pool.size)])
    }

    /** 下一个词，到末尾回到开头。录音、分析期间不可换词 */
    fun loadNext() {
        if (isBusy || mode != Mode.PRACTICE) return
        val total = practicePool.size
        if (total == 0) return
        store.practiceCursor = (normalizedCursor(total) + 1) % total
        loadCurrent()
    }

    /** 从词表里选了某个词。词表里没有就不动 */
    fun select(lexemeID: String) {
        if (isBusy || mode != Mode.PRACTICE) return
        val i = practicePool.indexOfFirst { it.id == lexemeID }
        if (i < 0) return
        store.practiceCursor = i
        loadCurrent()
    }

    private fun normalizedCursor(total: Int) = ((store.practiceCursor % total) + total) % total

    private fun loadLexeme(lex: Lexeme) {
        lexeme = lex
        // 即时占位：几何理想轮廓。Android 不用系统 TTS 生成评分参照（各厂商语音不同），
        // 只有母语者录音能替换它
        reference = scorer.idealReference(lex.tones)
        referenceType = ReferenceType.IDEAL
        pendingReference = null
        learnerCurve = FloatArray(0)
        accumulatedCount = 0
        feedback = null
        consecutiveFailures = 0
        if (lex.audioFilename != null) {
            pendingReferenceFile = lex.audioFilename
            referenceReady = false
            stage = Stage.Preparing
        } else {
            pendingReferenceFile = null
            referenceReady = true
            stage = Stage.Ready
        }
        changed()
    }

    /**
     * 母语者录音提取完毕（[joy.pinyintone.core.audio.ReferenceShaper.f0Track]，tones 传空）。
     * 空数组 = 提取失败，保持理想轮廓。录音中到达的先暂存，录完再换——一次录音全程参照线不变。
     */
    fun applyReference(lexemeID: String, track: FloatArray, type: ReferenceType) {
        if (lexeme?.id != lexemeID) return
        pendingReferenceFile = null
        if (track.isEmpty()) { markReferenceReady(); return }
        if (isBusy) { pendingReference = track to type; return }
        reference = track
        referenceType = type
        markReferenceReady()
    }

    private fun markReferenceReady() {
        referenceReady = true
        if (stage == Stage.Preparing) stage = Stage.Ready
        changed()
    }

    private fun flushPendingReference() {
        pendingReference?.let { (t, type) -> reference = t; referenceType = type }
        pendingReference = null
        referenceReady = true
    }

    // ================= 自测 =================

    /** 学习者从次级菜单主动开始自测 */
    fun beginSelfTest() {
        if (isBusy) return
        val words = corpus.assessmentPool().map { it.id }
        if (words.isEmpty()) return
        mode = Mode.SELF_TEST
        selfTestFinished = false
        selfTest = SelfTestProgress(words)
        loadSelfTestWord()
    }

    /** 取消自测（任何时候都可以），或看完完成页返回。回到普通练习，不留任何锁定状态 */
    fun endSelfTest() {
        if (stage == Stage.Recording) cancelRecording()
        mode = Mode.PRACTICE
        selfTest = null
        selfTestFinished = false
        loadCurrent()
    }

    /** 自测里一词录完后（app 留一拍让「已录到」可见）进入下一词 */
    fun advanceSelfTest() {
        val st = selfTest ?: return
        if (mode != Mode.SELF_TEST || stage != Stage.SelfTestRecorded) return
        selfTest = st.copy(index = st.index + 1)
        loadSelfTestWord()
    }

    private fun loadSelfTestWord() {
        val id = selfTest?.currentID
        val lex = id?.let { corpus.lexeme(it) }
        if (lex == null) {
            selfTestFinished = true
            lexeme = null
            stage = Stage.Ready
            changed()
            return
        }
        loadLexeme(lex)
    }

    // ================= 录音 =================

    /**
     * 权限被拒（用户拒绝或此前已拒绝）。也落一条技术失败记录，
     * 否则「没给麦克风权限」在数据里完全不可见。
     */
    fun onPermissionDenied() {
        if (lexeme == null) return
        persistTechnicalRetry(FailureReason.PERMISSION_DENIED, 0)
        stage = Stage.Failed(Failure.MICROPHONE_DENIED)
        changed()
    }

    /** 从系统设置回来、权限已开：回到可录音（不需要重启 App） */
    fun onPermissionGranted() {
        if (failure != Failure.MICROPHONE_DENIED) return
        stage = if (referenceReady) Stage.Ready else Stage.Preparing
        changed()
    }

    /**
     * 开始一次录音：锁定参照、清空累积。返回 false 表示此刻不能录（参照未就绪等），
     * app 不应启动录音设备。返回 true 后 app 启动设备；启动失败要调 [onRecordingStartFailed]。
     */
    fun beginRecording(): Boolean {
        if (lexeme == null || !canRecord || stage == Stage.Recording || !referenceReady) return false
        accumulatedCount = 0
        learnerCurve = FloatArray(0)
        feedback = null
        lockedReference = reference
        lockedReferenceType = referenceType
        stage = Stage.Recording
        changed()
        return true
    }

    /**
     * 录音设备没能启动。**不得静默**（CLAUDE.md 禁令 11）：给出可执行的提示并落技术失败记录。
     * @param permissionDenied 失败是因为权限（被系统收回等）
     */
    fun onRecordingStartFailed(permissionDenied: Boolean) {
        if (stage != Stage.Recording) return
        accumulatedCount = 0
        persistTechnicalRetry(
            if (permissionDenied) FailureReason.PERMISSION_DENIED else FailureReason.LOW_SIGNAL_QUALITY, 0)
        flushPendingReference()
        stage = Stage.Failed(if (permissionDenied) Failure.MICROPHONE_DENIED else Failure.MICROPHONE_UNAVAILABLE)
        changed()
    }

    /** 录音线程算出的逐帧 F0（Hz，含 0 无声帧） */
    fun onF0Frames(hz: FloatArray) {
        if (stage != Stage.Recording) return
        if (accumulatedCount + hz.size > accumulated.size) {
            accumulated = accumulated.copyOf(maxOf(accumulated.size * 2, accumulatedCount + hz.size))
        }
        hz.copyInto(accumulated, accumulatedCount)
        accumulatedCount += hz.size
    }

    /** 刷新实时学习者曲线（app 节流调用，约 12 次 / 秒）。自测不画任何曲线 */
    fun refreshLiveCurve() {
        if (stage != Stage.Recording || mode != Mode.PRACTICE) return
        learnerCurve = f0.normalize(f0.clean(accumulated.copyOf(accumulatedCount)))
        changed()
    }

    /** 点一下开始、再点一下停止：第二下调这里（app 先停设备） */
    fun stopAndEvaluate(style: FeedbackStyle) {
        val lex = lexeme
        if (stage != Stage.Recording || lex == null) return
        stage = Stage.Analyzing
        val raw = accumulated.copyOf(accumulatedCount)
        accumulatedCount = 0

        val out = scorer.evaluate(raw, lockedReference, lex.tones)
        when (out) {
            is ToneScorer.Outcome.TechnicalRetry -> {
                // 技术失败与发音错误分开：不生成结果、不给等级，但仍落一条记录
                learnerCurve = FloatArray(0)
                persistTechnicalRetry(FailureReason.INSUFFICIENT_VOICED_FRAMES, out.voicedFrames)
                flushPendingReference()
                stage = Stage.Failed(Failure.NO_VOICE)
            }
            is ToneScorer.Outcome.Scored -> {
                if (!out.dtwScore.isFinite() || out.dtwScore < 0) {
                    learnerCurve = FloatArray(0)
                    persistTechnicalRetry(FailureReason.ANALYSIS_ERROR, out.voicedFrames)
                    flushPendingReference()
                    stage = Stage.Failed(Failure.ANALYSIS)
                } else {
                    val attempt = store.incrementAttempts(lex.id)   // 只有有效结果才算练过
                    val switched = lockedReference.isNotEmpty() && !lockedReference.contentEquals(reference)
                    sink.save(record(
                        lex, dtwScore = out.dtwScore.toDouble(), grade = out.grade.rawValue,
                        attempt = attempt, referenceType = lockedReferenceType.rawValue,
                        voicedFrames = out.voicedFrames,
                        qualityFlag = out.resultStatus == ToneScorer.ResultStatus.QUALITY_FLAGGED,
                        referenceSwitched = switched,
                        feedbackMode = if (mode == Mode.PRACTICE) style.rawValue else null,
                        resultStatus = out.resultStatus.rawValue, failureReason = null,
                    ))
                    flushPendingReference()
                    if (mode == Mode.SELF_TEST) {
                        // 自测：照常算分入库，但**不向学习者呈现**任何评价
                        learnerCurve = FloatArray(0)
                        stage = Stage.SelfTestRecorded
                    } else {
                        learnerCurve = out.normalized
                        feedback = Feedback(out.dtwScore, out.grade.rawValue, out.levelToneDropped,
                                            FeedbackScore.of(out.dtwScore, out.levelToneDropped))
                        consecutiveFailures = if (!out.passed) consecutiveFailures + 1 else 0
                        stage = Stage.Feedback
                    }
                }
            }
        }
        changed()
    }

    /** 用户主动放弃这次录音（离开页面、取消自测）。不分析、没有成绩、不落记录 */
    fun cancelRecording() {
        if (stage != Stage.Recording) return
        accumulatedCount = 0
        learnerCurve = FloatArray(0)
        flushPendingReference()
        stage = Stage.Ready
        changed()
    }

    /** 录音被系统打断（来电、音频焦点被抢、切到后台）。安全停下并如实记为中断 */
    fun onInterrupted() {
        if (stage != Stage.Recording) return
        accumulatedCount = 0
        learnerCurve = FloatArray(0)
        persistTechnicalRetry(FailureReason.RECORDING_INTERRUPTED, 0)
        flushPendingReference()
        stage = Stage.Failed(Failure.INTERRUPTED)
        changed()
    }

    /** 「再试一次」：清掉上次结果回到可录音状态 */
    fun clearFeedbackForRetry() {
        if (isBusy) return
        feedback = null
        learnerCurve = FloatArray(0)
        stage = if (referenceReady) Stage.Ready else Stage.Preparing
        changed()
    }

    // ================= 记录 =================

    private val phase get() = if (mode == Mode.SELF_TEST) TrainingPhase.SELF_TEST else TrainingPhase.TRAINING

    /** 技术失败：哨兵分、不给等级、**不自增尝试次数**（没录上不算练过） */
    private fun persistTechnicalRetry(reason: FailureReason, voicedFrames: Int) {
        val lex = lexeme ?: return
        sink.save(record(
            lex, dtwScore = RecordSentinel.NO_SCORE, grade = RecordSentinel.NO_GRADE,
            attempt = store.attempts(lex.id), referenceType = null, voicedFrames = voicedFrames,
            qualityFlag = false, referenceSwitched = false, feedbackMode = null,
            resultStatus = ToneScorer.ResultStatus.TECHNICAL_RETRY.rawValue,
            failureReason = reason.rawValue,
        ))
    }

    private fun record(
        lex: Lexeme, dtwScore: Double, grade: String, attempt: Int, referenceType: String?,
        voicedFrames: Int, qualityFlag: Boolean, referenceSwitched: Boolean,
        feedbackMode: String?, resultStatus: String, failureReason: String?,
    ) = TrainingRecord(
        id = newID(), deviceID = context.deviceID, classCode = null, role = context.role,
        groupAssignment = "n/a", lexemeID = lex.id, dtwScore = dtwScore, grade = grade,
        attemptNumber = attempt, timestampMillis = clock(), referenceType = referenceType,
        voicedFrameCount = voicedFrames, qualityFlag = qualityFlag,
        referenceSwitchedDuringAttempt = referenceSwitched, phase = phase.rawValue,
        wordSetID = lex.wordSet?.rawValue, presentationOrder = null,
        assessmentSetVersion = if (mode == Mode.SELF_TEST) ASSESSMENT_SET_VERSION else null,
        feedbackMode = feedbackMode, resultStatus = resultStatus, failureReason = failureReason,
        schemaVersion = RecordSchema.VERSION, appVersion = context.appVersion,
    )

    private fun changed() { onChange?.invoke() }

    companion object {
        /** 同词连续未通过此次数即提示可以换词（不是评价） */
        const val SKIP_HINT_THRESHOLD = 3
        /** 自测一词录完后停留多久再进下一词（让「已录到」可见） */
        const val SELF_TEST_ADVANCE_DELAY_MS = 700L
    }
}
