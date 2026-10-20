package joy.pinyintone.core.practice

import kotlin.math.max
import kotlin.math.roundToInt

/**
 * 面向用户的百分制得分（0–100，越高越好），只用于普通练习的显示。
 * 对应 Swift `FeedbackResult.score`：由归一化 DTW 分段线性映射，60 分 = 通关线（DTW 0.5）。
 * 被闸门拦下时不得高于 59（否则会出现「85 分但不通关」）。
 *
 * 这是形成性反馈，**不是语言能力等级**（CLAUDE.md「结果解释边界」）。
 */
object FeedbackScore {
    fun of(dtwScore: Float, levelToneDropped: Boolean): Int {
        val m = mapped(dtwScore)
        return if (levelToneDropped) minOf(59, m) else m
    }

    private fun mapped(dtwScore: Float): Int {
        val d = max(0f, dtwScore)
        val p = when {
            d < 0.2f -> 100 - (d / 0.2f) * 10
            d < 0.35f -> 90 - ((d - 0.2f) / 0.15f) * 15
            d < 0.5f -> 75 - ((d - 0.35f) / 0.15f) * 15
            else -> max(0f, 60 - ((d - 0.5f) / 0.5f) * 60)
        }
        // Swift 的 Float.rounded() 是「四舍五入、.5 远离零」；p ≥ 0，与 roundToInt 一致
        return p.roundToInt()
    }
}
