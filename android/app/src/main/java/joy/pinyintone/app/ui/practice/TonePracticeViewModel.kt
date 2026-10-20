package joy.pinyintone.app.ui.practice

import android.app.Application
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import joy.pinyintone.app.PinyintoneApp
import joy.pinyintone.app.audio.AudioRecorder
import joy.pinyintone.app.audio.SamplePlayer
import joy.pinyintone.core.audio.AudioFramer
import joy.pinyintone.core.audio.ReferenceShaper
import joy.pinyintone.core.audio.Wav
import joy.pinyintone.core.corpus.Lexeme
import joy.pinyintone.core.practice.FeedbackStyle
import joy.pinyintone.core.practice.ReferenceType
import joy.pinyintone.core.practice.TonePracticeSession
import joy.pinyintone.core.practice.TonePracticeSession.Stage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** 界面要的全部状态（一次快照） */
data class PracticeUi(
    val stage: Stage,
    val mode: TonePracticeSession.Mode,
    val lexeme: Lexeme?,
    val reference: FloatArray,
    val learner: FloatArray,
    val feedback: TonePracticeSession.Feedback?,
    val consecutiveFailures: Int,
    val selfTest: TonePracticeSession.SelfTestProgress?,
    val selfTestFinished: Boolean,
    val progress: Pair<Int, Int>,
    val canRecord: Boolean,
    val isBusy: Boolean,
    val words: List<Lexeme>,
) {
    val isRecording: Boolean get() = stage == Stage.Recording
    val failure: TonePracticeSession.Failure? get() = (stage as? Stage.Failed)?.failure
}

/**
 * 声调练习页的 ViewModel：把 core 的 [TonePracticeSession]（状态机与记录）接上
 * 录音设备、示范播放和本地存储。评分参数一律在 core 里，这里不碰。
 */
class TonePracticeViewModel(app: Application) : AndroidViewModel(app) {

    private val deps = app as PinyintoneApp
    private val session = TonePracticeSession(deps.corpus, deps.practiceStore, deps.recordSink, deps.recordContext)
    private val recorder = AudioRecorder(app)
    val player = SamplePlayer(app)

    private val _ui = MutableStateFlow(snapshot())
    val ui: StateFlow<PracticeUi> = _ui

    /** 显示模式（学习者自选，默认曲线）。切换不影响评分 */
    private val _style = MutableStateFlow(deps.practiceStore.feedbackStyle)
    val style: StateFlow<FeedbackStyle> = _style

    private var lastCurveRefresh = 0L
    private var selfTestAdvance: Job? = null
    private var loadingReferenceFor: String? = null

    init {
        session.onChange = {
            _ui.value = snapshot()
            maybeLoadRealReference()
        }
        player.onPlaybackStarted = {
            // 示范实际开始发声。研究流程接入后在这里记 model_audio_started（不在点击时记）
        }
        session.loadCurrent()
    }

    private fun snapshot() = PracticeUi(
        stage = session.stage, mode = session.mode, lexeme = session.lexeme,
        reference = session.displayReference, learner = session.learnerCurve, feedback = session.feedback,
        consecutiveFailures = session.consecutiveFailures, selfTest = session.selfTest,
        selfTestFinished = session.selfTestFinished, progress = session.progress,
        canRecord = session.canRecord, isBusy = session.isBusy, words = session.practicePool,
    )

    // ---------- 选词与模式 ----------

    fun next() { stopSample(); session.loadNext() }
    fun select(id: String) { stopSample(); session.select(id) }
    fun tryAgain() { session.clearFeedbackForRetry() }

    fun setStyle(style: FeedbackStyle) {
        if (session.isBusy) return   // 录音、分析中换模式会让「看到的线 ≠ 评分的线」
        _style.value = style
        deps.practiceStore.feedbackStyle = style
    }

    fun beginSelfTest() { stopSample(); session.beginSelfTest() }

    fun endSelfTest() {
        selfTestAdvance?.cancel()
        if (session.isRecording) recorder.stop()
        session.endSelfTest()
    }

    // ---------- 示范 ----------

    /** 再点一次 = 停止。自测不提供示范；录音中不能播放 */
    fun toggleSample() {
        if (session.mode != TonePracticeSession.Mode.PRACTICE || session.isBusy) return
        if (player.playing.value) { player.stop(); return }
        session.lexeme?.let { player.speak(it.hanzi) }
    }

    private fun stopSample() = player.stop()

    // ---------- 录音（点一下开始，再点一下停止） ----------

    fun toggleRecording() {
        if (session.isRecording) stopAndEvaluate() else startRecording()
    }

    private fun startRecording() {
        stopSample()   // 示范与录音互斥
        if (!session.beginRecording()) return
        lastCurveRefresh = 0L
        try {
            recorder.start(object : AudioRecorder.Listener {
                override fun onF0(hz: FloatArray) {
                    session.onF0Frames(hz)
                    // 实时曲线节流（≈12 fps）：每帧都重算整条会拖慢主线程
                    val now = SystemClock.uptimeMillis()
                    if (now - lastCurveRefresh >= CURVE_REFRESH_MS) {
                        lastCurveRefresh = now
                        session.refreshLiveCurve()
                    }
                }

                override fun onInterrupted() {
                    recorder.stop()
                    session.onInterrupted()
                }
            })
        } catch (e: AudioRecorder.StartException) {
            // 不得静默（禁令 11）：状态机给出可执行提示并落技术失败记录
            session.onRecordingStartFailed(e.permissionDenied)
        }
    }

    private fun stopAndEvaluate() {
        recorder.stop()
        session.stopAndEvaluate(_style.value)
        if (session.stage == Stage.SelfTestRecorded) {
            selfTestAdvance?.cancel()
            selfTestAdvance = viewModelScope.launch {
                delay(TonePracticeSession.SELF_TEST_ADVANCE_DELAY_MS)
                session.advanceSelfTest()
            }
        }
    }

    // ---------- 权限 ----------

    fun onPermissionDenied() = session.onPermissionDenied()

    /** 回到前台时：权限若已在系统设置里打开，回到可录音；也重查中文语音 */
    fun onResumed(micGranted: Boolean) {
        if (micGranted) session.onPermissionGranted()
        player.checkChineseVoice()
    }

    /** 切到后台：不在后台持续录音；正在录的这一次如实记为中断 */
    fun onBackgrounded() {
        if (session.isRecording) {
            recorder.stop()
            session.onInterrupted()
        }
        stopSample()
    }

    // ---------- 母语者参照（有录音文件时） ----------

    /**
     * 词条有 `audioFilename` 时，从 assets/reference/ 读 16 kHz WAV 提参照（与 iOS 相同：
     * 真人录音不做下倾矫正，tones 传空）。现在语料里都没有录音，这条路不会走到。
     */
    private fun maybeLoadRealReference() {
        val file = session.pendingReferenceFile ?: return
        val lexemeID = session.lexeme?.id ?: return
        if (loadingReferenceFor == lexemeID) return
        loadingReferenceFor = lexemeID
        viewModelScope.launch {
            val track = withContext(Dispatchers.Default) {
                runCatching {
                    val pcm = getApplication<Application>().assets.open("reference/$file").use {
                        Wav.readPcm16Mono16k(it.readBytes())
                    }
                    ReferenceShaper().f0Track(AudioFramer.floatSamples(pcm), emptyList())
                }.getOrDefault(FloatArray(0))
            }
            loadingReferenceFor = null
            session.applyReference(lexemeID, track, ReferenceType.REAL)
        }
    }

    override fun onCleared() {
        if (session.isRecording) {
            recorder.stop()
            session.cancelRecording()
        }
        player.shutdown()
    }

    private companion object {
        const val CURVE_REFRESH_MS = 80L
    }
}
