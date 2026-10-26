package joy.pinyintone.app.audio

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.Locale

/**
 * 「听示范」：暂时用系统 TextToSpeech 朗读。
 *
 * **只用于播放，不用于生成评分参照**——各厂商的 TTS 语音不同，拿它提参照曲线会让
 * 同一个词在不同手机上有不同的通关标准。评分参照只用母语者录音或理想轮廓。
 *
 * 没有中文语音时如实提示，并提供去系统设置下载的入口。
 * 「示范开始播放」只在引擎的 `onStart` 回调里报——点击、或 `speak` 返回成功都不等于开始发声
 * （CLAUDE.md：事件只在实际发生时记）。
 */
class SamplePlayer(context: Context) {

    enum class Availability { INITIALIZING, READY, MISSING_CHINESE_VOICE, UNAVAILABLE }

    private val main = Handler(Looper.getMainLooper())
    private val _availability = MutableStateFlow(Availability.INITIALIZING)
    val availability: StateFlow<Availability> = _availability
    private val _playing = MutableStateFlow(false)
    val playing: StateFlow<Boolean> = _playing

    /** 示范**真正开始发声**时回调（主线程）。研究事件以后挂在这里 */
    var onPlaybackStarted: (() -> Unit)? = null

    private var counter = 0
    private var tts: TextToSpeech? = null

    init {
        tts = TextToSpeech(context.applicationContext) { status ->
            main.post { onInit(status) }
        }
    }

    private fun onInit(status: Int) {
        val engine = tts
        if (status != TextToSpeech.SUCCESS || engine == null) {
            _availability.value = Availability.UNAVAILABLE
            return
        }
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                main.post {
                    _playing.value = true
                    onPlaybackStarted?.invoke()
                }
            }
            override fun onDone(utteranceId: String?) { main.post { _playing.value = false } }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { main.post { _playing.value = false } }
            override fun onError(utteranceId: String?, errorCode: Int) { main.post { _playing.value = false } }
            override fun onStop(utteranceId: String?, interrupted: Boolean) { main.post { _playing.value = false } }
        })
        checkChineseVoice()
    }

    /** 系统默认的 TTS 引擎包名（诊断页用，如 com.google.android.tts）；还没初始化好为 null */
    val engineName: String? get() = runCatching { tts?.defaultEngine }.getOrNull()?.takeIf { it.isNotBlank() }

    /** 从系统设置回来时重新检查（用户可能刚下载了中文语音） */
    fun checkChineseVoice() {
        val engine = tts ?: return
        if (_availability.value == Availability.UNAVAILABLE) return
        val result = engine.setLanguage(Locale.SIMPLIFIED_CHINESE)
        _availability.value = when (result) {
            TextToSpeech.LANG_MISSING_DATA, TextToSpeech.LANG_NOT_SUPPORTED -> Availability.MISSING_CHINESE_VOICE
            else -> Availability.READY
        }
        engine.setSpeechRate(0.8f)   // 放慢便于模仿（iOS 用 0.4 的 AVSpeech 语速，大致相当）
    }

    /** 开始朗读；返回是否已把请求交给引擎（**不等于**已开始发声） */
    fun speak(text: String): Boolean {
        val engine = tts ?: return false
        if (_availability.value != Availability.READY || text.isEmpty()) return false
        val id = "sample-${counter++}"
        return engine.speak(text, TextToSpeech.QUEUE_FLUSH, Bundle(), id) == TextToSpeech.SUCCESS
    }

    fun stop() {
        tts?.stop()
        _playing.value = false
    }

    fun shutdown() {
        tts?.shutdown()
        tts = null
    }
}
