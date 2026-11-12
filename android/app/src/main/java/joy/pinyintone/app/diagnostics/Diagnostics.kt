package joy.pinyintone.app.diagnostics

import android.content.Context
import android.os.Build
import joy.pinyintone.app.BuildConfig
import joy.pinyintone.app.PinyintoneApp
import joy.pinyintone.app.R
import joy.pinyintone.app.audio.SamplePlayer
import joy.pinyintone.core.audio.F0Extractor
import joy.pinyintone.core.practice.RecordSchema
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 诊断信息：试用的参与者复制后发给研究者，用来排查真机上的录音 / 示范问题。
 *
 * **只有技术信息**：不含录音内容、词条、分数，不含账号、设备号、姓名等任何身份信息
 * （本机的 deviceID 也不放进来）。手机型号是型号，不是序列号。
 */
data class Diagnostics(
    val appVersion: String,
    val buildType: String,
    val manufacturer: String,
    val model: String,
    val androidVersion: String,
    val apiLevel: Int,
    val inputSampleRate: Int,          // 0 = 还没成功录过
    val audioSource: String?,
    val latestAttempt: Attempt?,
    val chineseTts: SamplePlayer.Availability,
    val ttsEngine: String?,
    val systemLocale: String,
    val uiLanguage: String,
    val fontScale: Float,
    val updateCheck: String,
) {
    data class Attempt(val voicedFrameCount: Int, val resultStatus: String?, val failureReason: String?, val timeUtc: String)

    /** 走了降采样 = 输入不是 16 kHz（由 core 的 Resampler 降到 16 kHz） */
    val resampled: Boolean? get() = if (inputSampleRate == 0) null else inputSampleRate != F0Extractor.SAMPLE_RATE.toInt()

    /**
     * 复制 / 分享出去的文本。键名固定用英文，方便研究者对照，不随界面语言变化。
     */
    fun asText(): String = buildString {
        appendLine("Pinyintone diagnostics")
        appendLine("app_version: $appVersion ($buildType)")
        appendLine("record_schema: ${RecordSchema.VERSION}")
        appendLine("device: $manufacturer $model")
        appendLine("android: $androidVersion (API $apiLevel)")
        appendLine("input_sample_rate_hz: ${if (inputSampleRate == 0) "none_yet" else inputSampleRate}")
        appendLine("resampled_to_16k: ${resampled?.toString() ?: "none_yet"}")
        appendLine("audio_source: ${audioSource ?: "none_yet"}")
        val a = latestAttempt
        if (a == null) {
            appendLine("last_attempt: none")
        } else {
            appendLine("last_attempt_time_utc: ${a.timeUtc}")
            appendLine("last_attempt_voiced_frames: ${a.voicedFrameCount}")
            appendLine("last_attempt_status: ${a.resultStatus ?: "unknown"}")
            appendLine("last_attempt_failure_reason: ${a.failureReason ?: "-"}")
        }
        appendLine("chinese_tts: ${chineseTts.name.lowercase()}")
        appendLine("tts_engine: ${ttsEngine ?: "none"}")
        appendLine("system_locale: $systemLocale")
        appendLine("ui_language: $uiLanguage")
        appendLine("font_scale: $fontScale")
        append("update_check: $updateCheck")
    }

    companion object {
        suspend fun collect(context: Context, player: SamplePlayer): Diagnostics {
            val app = context.applicationContext as PinyintoneApp
            val store = app.practiceStore
            val latest = app.database.records().latestAttempt()
            val config = context.resources.configuration
            val locale = config.locales[0]
            return Diagnostics(
                appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
                buildType = BuildConfig.BUILD_TYPE,
                manufacturer = Build.MANUFACTURER.orEmpty(),
                model = Build.MODEL.orEmpty(),
                androidVersion = Build.VERSION.RELEASE.orEmpty(),
                apiLevel = Build.VERSION.SDK_INT,
                inputSampleRate = store.lastInputSampleRate,
                audioSource = store.lastAudioSource,
                latestAttempt = latest?.let {
                    Attempt(it.voicedFrameCount, it.resultStatus, it.failureReason, utc(it.timestampMillis))
                },
                chineseTts = player.availability.value,
                ttsEngine = player.engineName,
                systemLocale = locale.toLanguageTag(),
                // 实际生效的界面语言 = 系统语言落到了哪一套资源上（en / zh / fr / ar）
                uiLanguage = context.getString(R.string.ui_language_code),
                fontScale = config.fontScale,
                updateCheck = app.updates.lastCheck,
            )
        }

        private fun utc(millis: Long): String =
            SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
                .format(Date(millis))
    }
}
