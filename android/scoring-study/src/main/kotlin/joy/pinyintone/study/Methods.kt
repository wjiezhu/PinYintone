package joy.pinyintone.study

import joy.pinyintone.core.audio.DTWAnalyzer
import joy.pinyintone.core.audio.ToneDirectionGate
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.log2

/**
 * 候选修法（只存在于实验里）。每种修法输入相同：
 * 归一化参照、归一化学习者序列、学习者 clean 后的原始 Hz、目标声调；输出分数与是否通关。
 *
 * 平调词走向闸门（全一声、首末下滑 > 3 半音）在所有修法里**照旧保留**，
 * 所以一声词的行为只受 DTW 部分改动的影响。
 */

/** DTW 对齐结果：总代价、最优路径（从 (0,0) 到 (m-1,n-1)，0 基）。 */
class Alignment(val total: Float, val path: List<IntArray>, val a: FloatArray, val b: FloatArray) {
    val pathLen get() = path.size

    /** 每个参照帧：对齐到它的学习者帧的平均代价，再对参照帧求平均 */
    fun refFrameMean(): Float {
        val sum = FloatArray(a.size); val cnt = IntArray(a.size)
        for (p in path) { sum[p[0]] += abs(a[p[0]] - b[p[1]]); cnt[p[0]]++ }
        var s = 0f
        for (i in a.indices) s += sum[i] / cnt[i]
        return s / a.size
    }

    /** 对称版：参照帧平均与学习者帧平均取较大者 */
    fun symmetricFrameMean(): Float {
        val sum = FloatArray(b.size); val cnt = IntArray(b.size)
        for (p in path) { sum[p[1]] += abs(a[p[0]] - b[p[1]]); cnt[p[1]]++ }
        var s = 0f
        for (j in b.indices) s += sum[j] / cnt[j]
        return maxOf(refFrameMean(), s / b.size)
    }
}

object Dtw {
    /**
     * 与 [DTWAnalyzer.distance] 同一递推与同一平局规则（对角 > 上 > 左），
     * 另可加 Sakoe-Chiba 带宽（|i·n/m − j| ≤ band，按长度比例斜置）。band = null 即不限。
     * 输入为已去掉 0 帧的序列。
     */
    fun align(a: FloatArray, b: FloatArray, band: Int? = null): Alignment {
        val m = a.size; val n = b.size
        val inf = Float.POSITIVE_INFINITY
        val dp = Array(m + 1) { FloatArray(n + 1) { inf } }
        val prev = Array(m + 1) { ByteArray(n + 1) }
        dp[0][0] = 0f
        for (i in 1..m) {
            for (j in 1..n) {
                if (band != null) {
                    val center = (i - 1).toFloat() * (n - 1).coerceAtLeast(1) / (m - 1).coerceAtLeast(1)
                    if (abs(center - (j - 1)) > band) continue
                }
                val cost = abs(a[i - 1] - b[j - 1])
                val up = dp[i - 1][j]; val left = dp[i][j - 1]; val diag = dp[i - 1][j - 1]
                val best = minOf(diag, minOf(up, left))
                if (best == inf) continue
                dp[i][j] = cost + best
                prev[i][j] = if (best == diag) 3 else if (best == up) 1 else 2
            }
        }
        val path = ArrayList<IntArray>()
        var i = m; var j = n
        while (i > 0 && j > 0) {
            path.add(intArrayOf(i - 1, j - 1))
            when (prev[i][j].toInt()) { 1 -> i -= 1; 2 -> j -= 1; else -> { i -= 1; j -= 1 } }
        }
        // 生产代码在边界上还会多数步（i 或 j 先到 0 时）；从 (1,1) 出发的合法路径不会走到那里
        path.reverse()
        return Alignment(dp[m][n], path, a, b)
    }

    fun voiced(x: FloatArray) = x.filter { it != 0f }.toFloatArray()

    /** 线性插值重采样到 n 点 */
    fun resample(xs: FloatArray, n: Int): FloatArray {
        if (xs.size < 2 || n < 2) return FloatArray(n) { xs.firstOrNull() ?: 0f }
        return FloatArray(n) { k ->
            val pos = k.toFloat() / (n - 1) * (xs.size - 1)
            val i = minOf(pos.toInt(), xs.size - 2)
            xs[i] + (xs[i + 1] - xs[i]) * (pos - i)
        }
    }
}

/**
 * 斜率限制的 DTW：连续的横步（只走学习者）或竖步（只走参照）各不超过 maxRun 步，
 * 即局部斜率限制在 [1/(maxRun+1), maxRun+1] 之间。状态 = (i, j, 上一步方向与连续步数)。
 * 返回 总代价 / 路径步数。
 */
fun slopeConstrainedDtw(a: FloatArray, b: FloatArray, maxRun: Int): Float {
    val m = a.size; val n = b.size
    val states = 2 * maxRun + 1          // 0 = 上一步对角；1..maxRun = 连续横步；maxRun+1.. = 连续竖步
    val inf = Float.POSITIVE_INFINITY
    val cost = Array(m) { Array(n) { FloatArray(states) { inf } } }
    val len = Array(m) { Array(n) { IntArray(states) } }
    cost[0][0][0] = abs(a[0] - b[0]); len[0][0][0] = 1
    for (i in 0 until m) for (j in 0 until n) {
        if (i == 0 && j == 0) continue
        val c = abs(a[i] - b[j])
        // 对角：从任何状态来
        if (i > 0 && j > 0) {
            var best = inf; var bl = 0
            for (s in 0 until states) if (cost[i - 1][j - 1][s] < best) { best = cost[i - 1][j - 1][s]; bl = len[i - 1][j - 1][s] }
            if (best < inf) { cost[i][j][0] = best + c; len[i][j][0] = bl + 1 }
        }
        // 横步（j 前进）：上一步是对角或横步且未满
        if (j > 0) for (r in 1..maxRun) {
            val from = if (r == 1) (listOf(0) + (maxRun + 1 until states)) else listOf(r - 1)
            var best = inf; var bl = 0
            for (s in from) if (cost[i][j - 1][s] < best) { best = cost[i][j - 1][s]; bl = len[i][j - 1][s] }
            if (best < inf) { cost[i][j][r] = best + c; len[i][j][r] = bl + 1 }
        }
        // 竖步（i 前进）
        if (i > 0) for (r in 1..maxRun) {
            val st = maxRun + r
            val from = if (r == 1) (0..maxRun).toList() else listOf(st - 1)
            var best = inf; var bl = 0
            for (s in from) if (cost[i - 1][j][s] < best) { best = cost[i - 1][j][s]; bl = len[i - 1][j][s] }
            if (best < inf) { cost[i][j][st] = best + c; len[i][j][st] = bl + 1 }
        }
    }
    var best = inf; var bl = 1
    for (s in 0 until states) if (cost[m - 1][n - 1][s] < best) { best = cost[m - 1][n - 1][s]; bl = len[m - 1][n - 1][s] }
    return best / bl
}

class ResampledSlope(id: String, label: String, val maxRun: Int) : Method(id, label) {
    override fun score(ref: FloatArray, cand: FloatArray): Float {
        val a = Dtw.voiced(ref); val b0 = Dtw.voiced(cand)
        if (a.isEmpty() || b0.isEmpty()) return DTWAnalyzer.MAX_SCORE
        return minOf(slopeConstrainedDtw(a, Dtw.resample(b0, a.size), maxRun), DTWAnalyzer.MAX_SCORE)
    }
}

/** 走势幅度：clean 后有声帧相对中位数的半音，P90 − P10（抗个别八度错误与首尾毛刺） */
fun spanSemitones(hz: FloatArray): Float? {
    val v = hz.filter { it > 0 }.sorted()
    if (v.size < 6) return null
    val med = v[v.size / 2]
    val st = v.map { 12 * log2(it / med) }
    fun pct(p: Double) = st[((st.size - 1) * p).toInt()]
    return pct(0.9) - pct(0.1)
}

/** C 闸门适用范围：词里至少有一个二 / 三 / 四声（全一声归平调闸门；1+5 不管） */
fun contourGateApplies(tones: List<Int>) = tones.any { it in 2..4 }

data class Verdict(val score: Float, val pass: Boolean, val gated: Boolean)

abstract class Method(val id: String, val label: String, val threshold: Float = 0.5f) {
    abstract fun score(ref: FloatArray, cand: FloatArray): Float
    open fun extraGate(hz: FloatArray, tones: List<Int>): Boolean = false

    fun judge(ref: FloatArray, cand: FloatArray, hz: FloatArray, tones: List<Int>): Verdict {
        val s = if (this is HistoricV3) scoreHz(ref, hz) else scoreWithTones(ref, cand, tones)
        val levelDrop = ToneDirectionGate.fails(hz, tones)     // 现有平调闸门，各修法都保留
        val extra = extraGate(hz, tones)
        val gated = levelDrop || extra
        return Verdict(s, !gated && s <= threshold, gated)
    }
}

private val production = DTWAnalyzer()

/** 现行：生产实现，总代价 / 最优路径步数 */
class Baseline : Method("BASE", "现行（÷路径步数）") {
    override fun score(ref: FloatArray, cand: FloatArray) = production.distance(ref, cand)
}

/** A 族：只改归一化分母 */
class DivideBy(id: String, label: String, val denom: (m: Int, n: Int, w: Int) -> Int, thr: Float = 0.5f)
    : Method(id, label, thr) {
    override fun score(ref: FloatArray, cand: FloatArray): Float {
        val a = Dtw.voiced(ref); val b = Dtw.voiced(cand)
        if (a.isEmpty() || b.isEmpty()) return DTWAnalyzer.MAX_SCORE
        val al = Dtw.align(a, b)
        return minOf(al.total / denom(a.size, b.size, al.pathLen), DTWAnalyzer.MAX_SCORE)
    }
}

/** A' 族：同一条路径，按「参照帧平均」（或双向取大）计分——相当于每个参照帧只算一票 */
class FrameMean(id: String, label: String, val symmetric: Boolean, thr: Float = 0.5f) : Method(id, label, thr) {
    override fun score(ref: FloatArray, cand: FloatArray): Float {
        val a = Dtw.voiced(ref); val b = Dtw.voiced(cand)
        if (a.isEmpty() || b.isEmpty()) return DTWAnalyzer.MAX_SCORE
        val al = Dtw.align(a, b)
        return minOf(if (symmetric) al.symmetricFrameMean() else al.refFrameMean(), DTWAnalyzer.MAX_SCORE)
    }
}

/**
 * B 族：先把学习者有声序列线性重采样到参照的长度，再做（可加带宽的）DTW，÷ 路径步数。
 * @param bandFrac Sakoe-Chiba 半宽占长度的比例；null = 不限
 */
class Resampled(id: String, label: String, val bandFrac: Float?, thr: Float = 0.5f) : Method(id, label, thr) {
    override fun score(ref: FloatArray, cand: FloatArray): Float {
        val a = Dtw.voiced(ref); val b0 = Dtw.voiced(cand)
        if (a.isEmpty() || b0.isEmpty()) return DTWAnalyzer.MAX_SCORE
        val b = Dtw.resample(b0, a.size)
        val band = bandFrac?.let { ceil(it * a.size).toInt().coerceAtLeast(1) }
        val al = Dtw.align(a, b, band)
        return minOf(al.total / al.pathLen, DTWAnalyzer.MAX_SCORE)
    }
}

/** C：在任一 DTW 修法之上，加走势幅度闸门 */
class WithSpanGate(val inner: Method, val minSpanSt: Float)
    : Method("${inner.id}+C${minSpanSt.toInt()}", "${inner.label} + 幅度闸门 ${minSpanSt.toInt()} 半音", inner.threshold) {
    override fun score(ref: FloatArray, cand: FloatArray) = inner.score(ref, cand)
    override fun extraGate(hz: FloatArray, tones: List<Int>): Boolean {
        if (!contourGateApplies(tones)) return false
        val span = spanSemitones(hz) ?: return false
        return span < minSpanSt
    }
}

/** 换阈值的同一方法（用于「0.5 要不要重新校准」） */
class Rethreshold(val inner: Method, thr: Float) : Method("${inner.id}@$thr", "${inner.label} 阈值 $thr", thr) {
    override fun score(ref: FloatArray, cand: FloatArray) = inner.score(ref, cand)
    override fun extraGate(hz: FloatArray, tones: List<Int>) = inner.extraGate(hz, tones)
}

/** 只对含二 / 三 / 四声的词换成 inner；全一声的词仍用现行 DTW（保持一声词逐位不变） */
class NonLevelOnly(val inner: Method) : Method("${inner.id}n", "${inner.label}（全一声词仍用现行）", inner.threshold) {
    private val base = Baseline()
    override fun score(ref: FloatArray, cand: FloatArray) = inner.score(ref, cand)
    fun scoreFor(ref: FloatArray, cand: FloatArray, tones: List<Int>) =
        if (contourGateApplies(tones)) inner.score(ref, cand) else base.score(ref, cand)
}

/** 带声调的分数（NonLevelOnly 需要知道声调） */
fun Method.scoreWithTones(ref: FloatArray, cand: FloatArray, tones: List<Int>): Float = when (this) {
    is NonLevelOnly -> scoreFor(ref, cand, tones)
    is WithSpanGate -> inner.scoreWithTones(ref, cand, tones)
    is Rethreshold -> inner.scoreWithTones(ref, cand, tones)
    else -> score(ref, cand)
}

/** 历史口径（schemaVersion ≤ 3）：学习者用无下限的纯 z-score，其余同现行。仅用于解释旧数据 */
class HistoricV3 : Method("V3", "历史 v1–v3（无归一化下限）") {
    private val base = Baseline()
    override fun score(ref: FloatArray, cand: FloatArray) = base.score(ref, cand)
    fun scoreHz(ref: FloatArray, hz: FloatArray) = base.score(ref, Pipeline.normalizeNoFloor(hz))
}

fun allMethods(): List<Method> {
    val base = Baseline()
    val aRef = DivideBy("A1", "÷参照长度 m", { m, _, _ -> m })
    val aMax = DivideBy("A2", "÷max(m,n)", { m, n, _ -> maxOf(m, n) })
    val aSum = DivideBy("A3", "÷(m+n)", { m, n, _ -> m + n })
    val aFm = FrameMean("A4", "参照帧平均", symmetric = false)
    val aFs = FrameMean("A5", "双向帧平均取大", symmetric = true)
    val b0 = Resampled("B0", "重采样等长", null)
    val b10 = Resampled("B10", "重采样 + 带宽 10%", 0.10f)
    val b20 = Resampled("B20", "重采样 + 带宽 20%", 0.20f)
    val b20n = NonLevelOnly(b20)
    return listOf(
        base, aRef, aMax, aSum, aFm, aFs, b0, b10, b20,
        WithSpanGate(base, 2f), WithSpanGate(base, 3f), WithSpanGate(base, 4f),
        WithSpanGate(b10, 2f), WithSpanGate(b20, 2f), WithSpanGate(b20n, 2f),
        Rethreshold(WithSpanGate(base, 2f), 0.35f), Rethreshold(WithSpanGate(b20n, 2f), 0.35f),
        HistoricV3(),
        ResampledSlope("Bs2", "重采样 + 斜率限制（连续横/竖步 ≤ 2）", 2),
        WithSpanGate(NonLevelOnly(ResampledSlope("Bs2", "重采样 + 斜率限制（连续横/竖步 ≤ 2）", 2)), 2f),
    )
}

fun methodIndex(id: String) = methods.indexOfFirst { it.id == id }.also { require(it >= 0) { id } }
