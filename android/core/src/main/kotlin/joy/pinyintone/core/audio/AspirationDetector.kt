package joy.pinyintone.core.audio

import kotlin.math.log10
import kotlin.math.sqrt

/**
 * 送气检测（「吹散蒲公英」模块）：动态底噪基线 + 15 dB 阈值。
 * 参数遵循 CLAUDE.md：
 * - 判定阈值：底噪 + 15 dB（启动后前 500 ms 采集底噪）
 * - 触发率通关线：≥ 0.6（600 ms 窗口内触发帧占比）
 *
 * 这里的「帧」是录音分片（1600 采样 = 0.1 s），不是 F0 的 512 帧；
 * 校准用前 5 片（500 ms），检测窗口 6 片（600 ms），见 iOS 的 `AspirationViewModel`。
 *
 * 对应 Swift：`PinYintone/Core/Audio/AspirationDetector.swift`。
 */
class AspirationDetector {

    /** 当前底噪基线（dB）；由 [calibrateBaseline] 写入 */
    var baselineDB: Float = Float.NEGATIVE_INFINITY
        private set

    /** 触发阈值（dB）= 底噪 + 15 dB */
    val thresholdDB: Float get() = baselineDB + THRESHOLD_OFFSET_DB

    /** 送入前 500 ms 的静音帧以校准底噪基线 */
    fun calibrateBaseline(frames: List<FloatArray>) {
        val total = frames.sumOf { it.size }
        if (total == 0) return
        val all = FloatArray(total)
        var p = 0
        for (f in frames) { f.copyInto(all, p); p += f.size }
        baselineDB = decibels(all)
    }

    /** 判断单帧是否触发送气（能量 > 底噪 + 15 dB） */
    fun detect(frame: FloatArray): Boolean {
        if (frame.isEmpty()) return false
        return decibels(frame) > thresholdDB
    }

    /** 计算一段帧序列的触发率（触发帧占比，0–1） */
    fun triggerRate(frames: List<FloatArray>): Float {
        if (frames.isEmpty()) return 0f
        val hits = frames.count { detect(it) }
        return hits.toFloat() / frames.size.toFloat()
    }

    /** 帧的 RMS 能量转分贝；下限钳制避免 log(0)。Swift: vDSP_rmsqv（此处 Double 累加） */
    fun decibels(samples: FloatArray): Float {
        var acc = 0.0
        for (s in samples) acc += (s * s).toDouble()
        val rms = sqrt(acc / samples.size).toFloat()
        return 20 * log10(maxOf(rms, 1e-7f))
    }

    companion object {
        /** 阈值高于底噪的 dB 增量（CLAUDE.md：+15 dB） */
        const val THRESHOLD_OFFSET_DB: Float = 15f

        /** 触发率通关线（CLAUDE.md：≥ 0.6） */
        const val PASS_TRIGGER_RATE: Float = 0.6f

        /** 底噪校准片数：5 × 0.1 s = 500 ms */
        const val CALIBRATION_CHUNKS: Int = 5

        /** 检测窗口片数：6 × 0.1 s = 600 ms */
        const val WINDOW_CHUNKS: Int = 6

        /** 录音分片长度：1600 采样 = 0.1 s @ 16 kHz */
        const val CHUNK_SIZE: Int = 1600
    }
}
