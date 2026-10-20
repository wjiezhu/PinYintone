package joy.pinyintone.core.audio

import kotlin.math.log2

/**
 * 非一声词的走势幅度闸门：DTW 判不出「读平」，这里补一刀。
 * 对应 Swift：`PinYintone/Core/Audio/ToneContourSpanGate.swift`，逐步相同，改动须两边同步。
 *
 * DTW 比的是 z-score 归一化后的形状，归一化尺度不变：1 个半音的漂移和 10 个半音的四声
 * 被拉成同样大小的曲线。只能在保留幅度的标度（相对的半音）上判。
 * 与 [ToneDirectionGate] 方向相反、适用范围不重叠：那道门只管全一声的词（该平却掉），
 * 这道门只管含二 / 三 / 四声的词（该动却没动），从不因为有起伏而判错。1+5 两道都不管。
 * 依据见 docs/SCORING_FLAT_READING_STUDY.md。
 */
object ToneContourSpanGate {

    /** 走势跨度下限（半音）。低于此值 = 读平，不通关 */
    const val MIN_SPAN_SEMITONES: Float = 2.0f

    /** 计算跨度所需的最少有声帧 */
    const val MIN_VOICED_FRAMES: Int = 6

    /** 该词是否适用：至少有一个二 / 三 / 四声 */
    fun applies(tones: List<Int>): Boolean = tones.any { it in 2..4 }

    /**
     * 走势跨度（半音）：有声帧排序后，P90 与 P10 的音程；分位取下标 `((count − 1) × p).toInt()`，不插值。
     * **必须传原始 Hz 轨迹**（clean 之后、归一化之前）。有声帧少于 [MIN_VOICED_FRAMES] 返回 null。
     * 与词的声调无关，任何词都可计算。Double 计算再转 Float，与 Swift 一致。
     */
    fun spanSemitones(hzTrack: FloatArray): Float? {
        val voiced = hzTrack.filter { it > 0f }.sorted()
        if (voiced.size < MIN_VOICED_FRAMES) return null
        val last = (voiced.size - 1).toDouble()
        val p10 = voiced[(last * 0.1).toInt()].toDouble()
        val p90 = voiced[(last * 0.9).toInt()].toDouble()
        return (12.0 * log2(p90 / p10)).toFloat()
    }

    /** 是否判定为「读平」：适用的词、跨度可算、且小于下限 */
    fun fails(hzTrack: FloatArray, tones: List<Int>): Boolean {
        if (!applies(tones)) return false
        val span = spanSemitones(hzTrack) ?: return false
        return span < MIN_SPAN_SEMITONES
    }
}
