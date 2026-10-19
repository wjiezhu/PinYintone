package joy.pinyintone.core.audio

import kotlin.math.log2

/**
 * 平调词的走向闸门：全一声的词首末下滑超过 3 个半音 = 不通关（不论 DTW 分数）。
 *
 * DTW 比的是归一化后的形状，尺度不变，判不出全一声词读成一路下滑；
 * 这一刀必须在保留音程幅度的标度上下——**必须传原始 Hz**（CLAUDE.md 禁令 15），
 * 且只管全一声的词（禁令 16）。
 *
 * 对应 Swift：`PinYintone/Core/Audio/ToneDirectionGate.swift`。
 */
object ToneDirectionGate {

    /** 全平调词允许的最大首末下滑（半音） */
    const val MAX_FALL_SEMITONES: Float = 3.0f

    /** 该词是否全部为一声（闸门只对这类词生效） */
    fun applies(tones: List<Int>): Boolean = tones.isNotEmpty() && tones.all { it == 1 }

    /**
     * 首末三分之一的落差（半音，负 = 下滑）。**必须传原始 Hz 轨迹**。
     * 词不适用或有声帧太少时返回 null。
     */
    fun fallSemitones(hzTrack: FloatArray, tones: List<Int>): Float? {
        if (!applies(tones)) return null
        val voiced = hzTrack.filter { it > 0 }
        if (voiced.size < 6) return null

        val third = maxOf(1, voiced.size / 3)
        // 与 Swift 的 reduce(0, +) 同为 Float 顺序累加，逐位一致
        var headSum = 0f
        for (k in 0 until third) headSum += voiced[k]
        var tailSum = 0f
        for (k in voiced.size - third until voiced.size) tailSum += voiced[k]
        val head = headSum / third.toFloat()
        val tail = tailSum / third.toFloat()
        if (head <= 0 || tail <= 0) return null
        return 12 * log2(tail / head)
    }

    /** 是否判定为「掉调」——全平调词下滑超过阈值。 */
    fun fails(hzTrack: FloatArray, tones: List<Int>): Boolean {
        val fall = fallSemitones(hzTrack, tones) ?: return false
        return fall < -MAX_FALL_SEMITONES
    }
}
