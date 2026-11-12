package joy.pinyintone.core.audio

import kotlin.math.abs

/** 评分等级。`rawValue` 与 iOS 的 `FeedbackGrade` 原始值一致（入库 / 上报用）。 */
enum class FeedbackGrade(val rawValue: String) {
    EXCELLENT("excellent"),         // DTW < 0.2
    GOOD("good"),                   // DTW 0.2–0.35
    NEEDS_PRACTICE("needsPractice"), // DTW 0.35–0.5（含 0.5，仍算通关）
    FAIL("fail"),                   // DTW > 0.5
}

/**
 * 归一化动态时间规整（路径长度归一化 DTW，参考 Richter & Guðnason 2023）。
 * 参数遵循 CLAUDE.md：欧氏距离（标量即 |Δ|）、作用于归一化 F0、忽略 0 帧、通关线 ≤ 0.5。
 *
 * 对应 Swift：`PinYintone/Core/Audio/DTWAnalyzer.swift`。
 * 只有 Float 加法 / 比较，给定相同输入与 Swift 逐位一致（含平局时的回溯方向）。
 */
class DTWAnalyzer {

    /** 计算两条 F0 序列的归一化 DTW 距离（值域 0–[MAX_SCORE]，越小越接近） */
    fun distance(reference: FloatArray, candidate: FloatArray): Float {
        // CLAUDE.md：DTW 对齐时忽略 0 帧（无声帧）
        val a = reference.filter { it != 0f }
        val b = candidate.filter { it != 0f }
        val m = a.size
        val n = b.size
        if (m == 0 || n == 0) return MAX_SCORE

        val dp = Array(m + 1) { FloatArray(n + 1) { Float.POSITIVE_INFINITY } }
        // prev：1=上方, 2=左方, 3=对角（用于回溯路径长度）
        val prev = Array(m + 1) { ByteArray(n + 1) }
        dp[0][0] = 0f

        for (i in 1..m) {
            for (j in 1..n) {
                val cost = abs(a[i - 1] - b[j - 1])
                val up = dp[i - 1][j]
                val left = dp[i][j - 1]
                val diag = dp[i - 1][j - 1]
                val best = minOf(diag, minOf(up, left))
                dp[i][j] = cost + best
                prev[i][j] = if (best == diag) 3 else if (best == up) 1 else 2
            }
        }

        // 路径长度归一化：D_norm = D_dtw / W（W = 最优路径步数）
        val pathLen = tracePathLength(prev, m, n)
        return minOf(dp[m][n] / maxOf(pathLen, 1).toFloat(), MAX_SCORE)
    }

    /** 根据归一化 DTW 距离返回评分等级（CLAUDE.md 通关线 ≤ 0.5） */
    fun grade(dtwScore: Float): FeedbackGrade = when {
        dtwScore < 0.2f -> FeedbackGrade.EXCELLENT
        dtwScore < 0.35f -> FeedbackGrade.GOOD
        dtwScore <= 0.5f -> FeedbackGrade.NEEDS_PRACTICE
        else -> FeedbackGrade.FAIL   // >0.5 不通关（NaN 也落在这里，与 Swift switch 的 default 相同）
    }

    /** 是否通关（归一化 DTW ≤ 0.5） */
    fun passed(dtwScore: Float): Boolean = dtwScore <= PASS_THRESHOLD

    /**
     * 把参照与候选序列各等分为 nSegments 段，对每段独立计算归一化 DTW（按字粒度反馈）。
     * 某段任意一侧无有效帧则该段返回 [MAX_SCORE]。
     */
    fun segmentScores(reference: FloatArray, candidate: FloatArray, nSegments: Int): FloatArray {
        if (nSegments <= 0) return FloatArray(0)
        val a = reference.filter { it != 0f }.toFloatArray()
        val b = candidate.filter { it != 0f }.toFloatArray()
        if (a.isEmpty() || b.isEmpty()) return FloatArray(nSegments) { MAX_SCORE }

        return FloatArray(nSegments) { i ->
            val aSeg = a.copyOfRange((a.size * i) / nSegments, (a.size * (i + 1)) / nSegments)
            val bSeg = b.copyOfRange((b.size * i) / nSegments, (b.size * (i + 1)) / nSegments)
            if (aSeg.isEmpty() || bSeg.isEmpty()) MAX_SCORE else distance(aSeg, bSeg)
        }
    }

    private fun tracePathLength(prev: Array<ByteArray>, m: Int, n: Int): Int {
        var i = m
        var j = n
        var steps = 0
        while (i > 0 || j > 0) {
            steps += 1
            if (i <= 0 || j <= 0) {
                if (i > 0) i -= 1 else j -= 1
                continue
            }
            when (prev[i][j].toInt()) {
                1 -> i -= 1              // 上方
                2 -> j -= 1              // 左方
                else -> { i -= 1; j -= 1 } // 对角
            }
        }
        return steps
    }

    companion object {
        /**
         * 评分上限（有限哨兵值）。任一侧无有声帧时返回此值而非 Infinity
         * （Infinity 无法 JSON 编码）。9.99 远超通关线，语义仍是 fail。
         */
        const val MAX_SCORE: Float = 9.99f

        /** 通关线（CLAUDE.md）：归一化 DTW ≤ 0.5 */
        const val PASS_THRESHOLD: Float = 0.5f
    }
}
