package joy.pinyintone.app.audio

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioRecordingConfiguration
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import joy.pinyintone.core.audio.AudioFramer
import joy.pinyintone.core.audio.F0Extractor
import joy.pinyintone.core.audio.PcmChunker
import java.util.concurrent.Executor

/**
 * 录音：AudioRecord（单声道 PCM16，音源 VOICE_RECOGNITION）→ 16 kHz → 1600 采样一片 →
 * 帧化（512 / 128）→ YIN，逐片把 F0 送回主线程。对应 iOS `AudioEngine` + `AudioFramer` 的录音部分。
 *
 * 采样率：优先 16 kHz（CLAUDE.md 锁定的分析采样率）；部分机型 16 kHz 初始化失败，
 * 就用硬件原生采样率录，再由 core 的 `Resampler` 降到 16 kHz。**评分永远在 16 kHz 上做。**
 *
 * VOICE_RECOGNITION 音源在多数机型上关掉了自动增益与降噪，F0 不被处理链扭曲。
 * 原始录音只在内存里流过，不落盘、不上传。
 */
class AudioRecorder(context: Context) {

    interface Listener {
        /** 这一片（0.1 s）里逐帧的 F0（Hz，含 0 无声帧）。主线程 */
        fun onF0(hz: FloatArray)
        /** 录音中途失败或被系统打断（来电、被别的应用占用、读出错）。主线程 */
        fun onInterrupted()
    }

    /** 启动失败。调用方必须给出可执行的重录提示，不得静默（CLAUDE.md 禁令 11） */
    class StartException(val permissionDenied: Boolean, message: String) : Exception(message)

    private val appContext = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var running = false
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    private var callback: Any? = null   // AudioManager.AudioRecordingCallback（API 29+）

    /** 实际使用的硬件采样率（诊断用） */
    var inputSampleRate: Int = 0
        private set

    val isRunning: Boolean get() = running

    @SuppressLint("MissingPermission")   // 下面显式检查
    fun start(listener: Listener) {
        check(!running) { "already recording" }
        if (ContextCompat.checkSelfPermission(appContext, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED) {
            throw StartException(permissionDenied = true, "RECORD_AUDIO not granted")
        }
        val rec = open() ?: throw StartException(false, "no AudioRecord configuration could be initialised")
        try {
            rec.startRecording()
        } catch (e: IllegalStateException) {
            rec.release()
            throw StartException(false, "startRecording failed: ${e.message}")
        } catch (e: SecurityException) {
            rec.release()
            throw StartException(true, "startRecording denied: ${e.message}")
        }
        if (rec.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            rec.release()
            // 麦克风被别的应用占着时常见
            throw StartException(false, "recordingState=${rec.recordingState}")
        }
        record = rec
        running = true
        watchSilencing(rec, listener)

        val rate = inputSampleRate
        thread = Thread({ loop(rec, rate, listener) }, "pinyintone-recorder").apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    /** 停止（点第二下、离开页面、被打断后）。可重复调用 */
    fun stop() {
        running = false
        thread?.let { if (it !== Thread.currentThread()) it.join(500) }
        thread = null
        unwatchSilencing()
        record?.let {
            try { it.stop() } catch (_: IllegalStateException) {}
            it.release()
        }
        record = null
    }

    private fun loop(rec: AudioRecord, rate: Int, listener: Listener) {
        val f0 = F0Extractor()
        val framer = AudioFramer()
        val chunker = PcmChunker(rate)
        val pending = ArrayList<Float>(16)
        framer.onFrame = { pending.add(f0.extract(it)) }
        chunker.onChunk = { chunk ->
            framer.feed(chunk)
            val batch = pending.toFloatArray()
            pending.clear()
            main.post { if (running) listener.onF0(batch) }
        }
        val buf = ShortArray(maxOf(rate / 50, 256))   // 20 ms
        while (running) {
            val n = rec.read(buf, 0, buf.size)
            if (n < 0) {
                // ERROR_INVALID_OPERATION / ERROR_DEAD_OBJECT 等：设备被收走
                main.post { if (running) listener.onInterrupted() }
                break
            }
            if (n > 0) chunker.feed(buf, n)
        }
    }

    @SuppressLint("MissingPermission")
    private fun open(): AudioRecord? {
        for (rate in candidateRates()) {
            val minBuf = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minBuf <= 0) continue
            val rec = try {
                AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, rate,
                    AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(minBuf * 2, rate / 5 * 2))
            } catch (e: IllegalArgumentException) {
                null
            } catch (e: SecurityException) {
                throw StartException(true, "AudioRecord denied: ${e.message}")
            }
            if (rec != null && rec.state == AudioRecord.STATE_INITIALIZED) {
                inputSampleRate = rate
                return rec
            }
            rec?.release()
        }
        return null
    }

    /** 16 kHz 优先，其次硬件原生采样率，再兜底常见值 */
    private fun candidateRates(): List<Int> {
        val am = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val native = am.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
        return listOfNotNull(16_000, native, 48_000, 44_100).distinct()
    }

    /**
     * API 29+：系统把我们的录音静音（来电、别的应用抢占麦克风）时当作打断。
     * 更早的系统没有这个回调，静音期间读到的是 0，结果会落到「没录到声音」——也是技术失败，不是低分。
     */
    private fun watchSilencing(rec: AudioRecord, listener: Listener) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val cb = object : AudioManager.AudioRecordingCallback() {
            override fun onRecordingConfigChanged(configs: MutableList<AudioRecordingConfiguration>) {
                val silenced = configs.any { it.clientAudioSessionId == rec.audioSessionId && it.isClientSilenced }
                if (silenced && running) main.post { if (running) listener.onInterrupted() }
            }
        }
        rec.registerAudioRecordingCallback(Executor { main.post(it) }, cb)
        callback = cb
    }

    private fun unwatchSilencing() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val cb = callback as? AudioManager.AudioRecordingCallback ?: return
        record?.unregisterAudioRecordingCallback(cb)
        callback = null
    }
}
