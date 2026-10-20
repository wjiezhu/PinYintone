package joy.pinyintone.study

import joy.pinyintone.core.audio.DTWAnalyzer
import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.pow
import kotlin.random.Random

/**
 * 「读平也通关」研究：原因拆解 + 修法对比。结果写到 results/ 目录下的 md（报告引用这里的数字）。
 * 运行：cd android && ./gradlew :scoring-study:run
 */

val repoRoot: File = File("../..").canonicalFile
val resultsDir = File("results").apply { mkdirs() }
val methods = allMethods()

enum class Cat(val zh: String, val shouldPass: Boolean) {
    CORRECT("正确（自然语流：半上 / 变调）", true),
    CITATION("正确（每个三声都读 214）", true),
    FLAT("读平", false),
    WRONG1("错一个字的调", false),
    WRONG2("两个字都错", false),
    T1_FLAT("一声词读平（这是对的）", true),
}

class Case(val target: List<Int>, val ref: String, val cat: Cat, val ratio: Float,
           val sex: String, val read: List<Int>, val v: List<Verdict>, val rate: Int = 0, val span: Float? = null)

fun f(x: Float, d: Int = 3) = String.format(Locale.ROOT, "%.${d}f", x)
fun pct(x: Double) = String.format(Locale.ROOT, "%.0f%%", x * 100)
fun tonesStr(t: List<Int>) = t.joinToString("+")

val twoSyl: List<List<Int>> = (1..4).flatMap { a -> (1..4).map { b -> listOf(a, b) } }.filter { it != listOf(3, 3) }
val targets: List<List<Int>> = twoSyl + listOf(listOf(4, 5), listOf(1, 5))

fun categorize(target: List<Int>, read: List<Int>): Cat? {
    val diff = target.indices.count { target[it] != read[it] }
    return when (diff) { 0 -> null; 1 -> Cat.WRONG1; else -> Cat.WRONG2 }
}

fun judgeAll(ref: FloatArray, l: Pipeline.Learner, tones: List<Int>) =
    methods.map { it.judge(ref, l.norm, l.cleaned, tones) }

// ───────────────────────────── 1. 原因拆解 ─────────────────────────────

fun causeStudy(sb: StringBuilder) {
    val f0 = Pipeline.f0
    val wav = File(repoRoot, "testdata/scoring/t4t4_read_flat.wav")
    val l = Pipeline.learner(Pipeline.rawHz(Pipeline.readWav(wav)))!!
    val ref = Pipeline.idealRef(listOf(4, 4))
    val prod = DTWAnalyzer().distance(ref, l.norm)
    val a = Dtw.voiced(ref); val b = Dtw.voiced(l.norm)
    val al = Dtw.align(a, b)
    check(abs(al.total / al.pathLen - prod) < 1e-6f) { "实验 DTW 与生产实现不一致" }

    sb.appendLine("## 1. t4t4_read_flat 拆解\n")
    sb.appendLine("- 现行分数（生产实现）：**${f(prod)}**（golden.json 记录 0.311）")
    sb.appendLine("- 参照有声帧 m = ${a.size}，学习者有声帧 n = ${b.size}（n/m = ${f(b.size.toFloat() / a.size, 2)}）")
    sb.appendLine("- DTW 总代价 D = ${f(al.total)}，最优路径步数 W = ${al.pathLen}，D/W = ${f(al.total / al.pathLen)}")
    val hz = l.cleaned.filter { it > 0 }
    sb.appendLine("- 学习者原始 Hz：${f(hz.min(), 1)}–${f(hz.max(), 1)}，均值 ${f(hz.average().toFloat(), 1)}；" +
        "sd = ${f(sd(hz), 3)} Hz，下限 = 均值×0.03 = ${f(hz.average().toFloat() * 0.03f, 2)} Hz → 除数取下限")
    sb.appendLine("- 归一化后学习者序列：${f(b.min())} … ${f(b.max())}，平均 |z| = ${f(b.map { abs(it) }.average().toFloat())}")
    sb.appendLine("- 参照序列平均 |z| = ${f(a.map { abs(it) }.average().toFloat())}（参照均值恰为 0）\n")

    // 路径上「停在同一参照帧、学习者帧前进」的横步
    var parked = 0; var parkedCost = 0f
    val perRef = IntArray(a.size)
    for (k in al.path.indices) {
        val p = al.path[k]; perRef[p[0]]++
        if (k > 0 && al.path[k - 1][0] == p[0]) { parked++; parkedCost += abs(a[p[0]] - b[p[1]]) }
    }
    val top = perRef.indices.sortedByDescending { perRef[it] }.take(3)
    sb.appendLine("路径上 ${al.pathLen} 步里，有 **$parked 步**是参照帧不动、学习者帧前进（把多出来的学习者帧「停」在同一个参照帧上），" +
        "这些步的代价合计只有 ${f(parkedCost)}（每步平均 ${f(parkedCost / parked)}）。")
    sb.appendLine("吸收学习者帧最多的参照帧：" + top.joinToString("；") { "第 $it 帧（z = ${f(a[it])}）吸收 ${perRef[it]} 帧" } + "。\n")

    // 反事实 2×2：下限 有/无 × 长度 原样/重采样到 m
    val noFloor = Dtw.voiced(Pipeline.normalizeNoFloor(l.cleaned))
    fun base(x: FloatArray) = DTWAnalyzer().distance(a, x)
    val eqLen = Dtw.resample(b, a.size)
    val eqLenNoFloor = Dtw.resample(noFloor, a.size)
    sb.appendLine("反事实（同一段录音，参照不变，只换一个条件）：\n")
    sb.appendLine("| 条件 | 学习者长度 | 归一化 | 现行 DTW |")
    sb.appendLine("|---|---|---|---|")
    sb.appendLine("| 现状 | ${b.size} 帧 | 带下限 | ${f(prod)} |")
    sb.appendLine("| 去掉长度因素 | 重采样到 ${a.size} 帧 | 带下限 | ${f(base(eqLen))} |")
    sb.appendLine("| 去掉下限（纯 z-score） | ${b.size} 帧 | 无下限 | ${f(base(noFloor))} |")
    sb.appendLine("| 两者都去掉 | ${a.size} 帧 | 无下限 | ${f(base(eqLenNoFloor))} |")
    sb.appendLine()
    // Shapley 分摊：两个因素各自「打开」时分数下降量的平均
    val s00 = base(eqLenNoFloor); val sLen = base(noFloor); val sFloor = base(eqLen); val s11 = prod
    val len = ((s00 - sLen) + (sFloor - s11)) / 2; val flo = ((s00 - sFloor) + (sLen - s11)) / 2
    sb.appendLine("两个因素合计把分数从 ${f(s00)} 压到 ${f(s11)}（−${f(s00 - s11)}）。按 Shapley 平均分摊：" +
        "**长度（路径步数稀释）−${f(len)}（${pct((len / (s00 - s11)).toDouble())}）**，" +
        "**归一化下限 −${f(flo)}（${pct((flo / (s00 - s11)).toDouble())}）**。\n")

    // 长度扫描：同一条读平序列按比例拉长 / 缩短
    sb.appendLine("长度扫描（把同一条读平序列线性拉伸到不同长度，参照 48 帧）：\n")
    sb.appendLine("| n/m | 0.5 | 0.75 | 1 | 1.25 | 1.5 | 1.83（原样） | 2 | 2.5 | 3 |")
    sb.appendLine("|---|---|---|---|---|---|---|---|---|---|")
    val ratios = listOf(0.5f, 0.75f, 1f, 1.25f, 1.5f, b.size.toFloat() / a.size, 2f, 2.5f, 3f)
    sb.appendLine("| 现行 DTW | " + ratios.joinToString(" | ") { f(base(Dtw.resample(b, (it * a.size).toInt()))) } + " |")
    sb.appendLine("| 学习者恒为 0⁺ 的极限 | " + ratios.joinToString(" | ") {
        f(base(FloatArray((it * a.size).toInt()) { 1e-4f }))
    } + " |\n")

    // 各修法对同一录音
    sb.appendLine("各修法对 t4t4_read_flat：\n")
    sb.appendLine("| 修法 | 分数 | 判定 |")
    sb.appendLine("|---|---|---|")
    for (m in methods) {
        val v = m.judge(ref, l.norm, l.cleaned, listOf(4, 4))
        sb.appendLine("| ${m.id} ${m.label} | ${f(v.score)} | ${if (v.pass) "通关 ❌" else if (v.gated) "闸门拦下 ✅" else "不通关 ✅"} |")
    }
    sb.appendLine()
}

fun sd(xs: List<Float>): Float {
    val m = xs.average(); return kotlin.math.sqrt(xs.map { (it - m) * (it - m) }.average()).toFloat()
}

// ───────────────────────────── 2. 合成测试集 ─────────────────────────────

val ratiosSyn = listOf(0.5f, 0.75f, 1f, 1.5f, 2f, 3f)

fun synthCases(refs: Map<List<Int>, Pipeline.Ref>, refName: String, reps: Int, seed: Int): List<Case> {
    val jobs = ArrayList<() -> Case?>()
    for (target in targets) {
        val ref = refs[target]!!.norm
        val m = Dtw.voiced(ref).size
        val readings = ArrayList<Pair<Cat, Synth.Reading>>()
        readings += Cat.CORRECT to Synth.Reading(target)
        if (target.contains(3)) readings += Cat.CITATION to Synth.Reading(target, natural = false)
        readings += (if (target.all { it == 1 }) Cat.T1_FLAT else Cat.FLAT) to Synth.Reading(target, flat = true)
        for (w in twoSyl) categorize(target, w)?.let { readings += it to Synth.Reading(w) }
        for ((cat, rd) in readings) for (ratio in ratiosSyn) for (sex in Synth.Sex.values()) for (r in 0 until reps) {
            val s = seed + jobs.size * 7919
            jobs += {
                val rnd = Random(s)
                val raw = Synth.track(rd, Synth.Options((ratio * m).toInt().coerceAtLeast(8), sex), rnd)
                Pipeline.learner(raw)?.let {
                    Case(target, refName, cat, ratio, sex.name, rd.tones, judgeAll(ref, it, target), span = spanSemitones(it.cleaned))
                }
            }
        }
    }
    return jobs.parallelStream().map { it() }.toList().filterNotNull()
}

fun passRate(cs: List<Case>, k: Int) = if (cs.isEmpty()) Double.NaN else cs.count { it.v[k].pass }.toDouble() / cs.size

/** 各修法总表 */
fun summaryTable(sb: StringBuilder, cases: List<Case>, title: String, ms: List<Int> = methods.indices.toList()) {
    val nonT1 = cases.filter { !it.target.all { t -> t == 1 } }
    val t1 = cases.filter { it.target.all { t -> t == 1 } }
    sb.appendLine("### $title\n")
    sb.appendLine("「正确」列是通关率（越高越好），其余是**拦下率**（越高越好）。最差语速 = 0.5–3 倍里正确读法通关率最低的那一档。" +
        "正确读法余量 = 0.5 − 正确读法分数的 95 分位（不含被闸门拦下的）。\n")
    sb.appendLine("| 修法 | 正确 | 正确·引用三声 | 读平 | 错一字 | 错两字 | 最差语速 正确 | 男/女 正确 | 男/女 读平拦下 | 正确余量 | 一声词：读平通关 / 读错拦下 |")
    sb.appendLine("|---|---|---|---|---|---|---|---|---|---|---|")
    for (k in ms) {
        val m = methods[k]
        fun r(cat: Cat, set: List<Case> = nonT1) = set.filter { it.cat == cat }
        val corr = r(Cat.CORRECT)
        val worstRatio = ratiosSyn.minOf { q -> passRate(corr.filter { it.ratio == q }, k) }
        val male = passRate(corr.filter { it.sex == "MALE" }, k); val fem = passRate(corr.filter { it.sex == "FEMALE" }, k)
        val flat = r(Cat.FLAT)
        val fm = 1 - passRate(flat.filter { it.sex == "MALE" }, k); val ff = 1 - passRate(flat.filter { it.sex == "FEMALE" }, k)
        val scores = corr.filter { !it.v[k].gated }.map { it.v[k].score }.sorted()
        val p95 = if (scores.isEmpty()) Float.NaN else scores[(scores.size * 0.95).toInt().coerceAtMost(scores.size - 1)]
        val t1ok = passRate(t1.filter { it.cat == Cat.T1_FLAT || it.cat == Cat.CORRECT }, k)
        val t1bad = 1 - passRate(t1.filter { !it.cat.shouldPass }, k)
        sb.appendLine("| ${m.id} ${m.label} | ${pct(passRate(corr, k))} | ${pct(passRate(r(Cat.CITATION), k))} | " +
            "${pct(1 - passRate(flat, k))} | ${pct(1 - passRate(r(Cat.WRONG1), k))} | ${pct(1 - passRate(r(Cat.WRONG2), k))} | " +
            "${pct(worstRatio)} | ${pct(male)}/${pct(fem)} | ${pct(fm)}/${pct(ff)} | ${f(m.threshold - p95, 2)} | ${pct(t1ok)} / ${pct(t1bad)} |")
    }
    sb.appendLine()
}

/** 按长度比例拆开：现行 vs 若干修法 */
fun ratioTable(sb: StringBuilder, cases: List<Case>, title: String, ks: List<Int>) {
    val nonT1 = cases.filter { !it.target.all { t -> t == 1 } }
    sb.appendLine("### $title\n")
    sb.appendLine("| 修法 | 类别 | " + ratiosSyn.joinToString(" | ") { "${f(it, 2)}×" } + " |")
    sb.appendLine("|---|---|" + ratiosSyn.joinToString("") { "---|" })
    for (k in ks) for (cat in listOf(Cat.CORRECT, Cat.FLAT, Cat.WRONG1, Cat.WRONG2)) {
        val cs = nonT1.filter { it.cat == cat }
        sb.appendLine("| ${methods[k].id} | ${cat.zh}${if (cat.shouldPass) "·通关" else "·通关（漏判）"} | " +
            ratiosSyn.joinToString(" | ") { q -> pct(passRate(cs.filter { it.ratio == q }, k)) } + " |")
    }
    sb.appendLine()
}

/** 现行算法：每个目标声调组合，读平的通关率（比例 1 与 ≥1.5 分开） */
fun perTargetFlat(sb: StringBuilder, cases: List<Case>, title: String, ks: List<Int>) {
    sb.appendLine("### $title\n")
    sb.appendLine("| 目标 | " + ks.joinToString(" | ") { "${methods[it].id} 读平 ≤1× / ≥1.5×" } + " | " +
        ks.joinToString(" | ") { "${methods[it].id} 正确" } + " | 现行 读平中位分 |")
    sb.appendLine("|---|" + ks.joinToString("") { "---|" } + ks.joinToString("") { "---|" } + "---|")
    for (t in targets.filter { !it.all { x -> x == 1 } }) {
        val flat = cases.filter { it.target == t && it.cat == Cat.FLAT }
        val corr = cases.filter { it.target == t && it.cat == Cat.CORRECT }
        val med = flat.map { it.v[0].score }.sorted().let { it[it.size / 2] }
        sb.appendLine("| ${tonesStr(t)} | " + ks.joinToString(" | ") { k ->
            "${pct(passRate(flat.filter { it.ratio <= 1f }, k))} / ${pct(passRate(flat.filter { it.ratio >= 1.5f }, k))}"
        } + " | " + ks.joinToString(" | ") { k -> pct(passRate(corr, k)) } + " | ${f(med)} |")
    }
    sb.appendLine()
}

/** 错调混淆：现行 vs 指定修法，各「读成的调」通关率（漏判率） */
fun confusionTable(sb: StringBuilder, cases: List<Case>, title: String, k: Int) {
    sb.appendLine("### $title\n")
    sb.appendLine("行 = 目标，列 = 实际读成的调；格内为通关率（对角线是正确读法，应高；其余是漏判，应低）。\n")
    val cols = twoSyl
    sb.appendLine("| 目标＼读成 | " + cols.joinToString(" | ") { tonesStr(it) } + " | 读平 |")
    sb.appendLine("|---|" + cols.joinToString("") { "---|" } + "---|")
    for (t in twoSyl) {
        val row = cols.map { c ->
            val cs = cases.filter { it.target == t && it.read == c && (it.cat == Cat.CORRECT || !it.cat.shouldPass) && it.cat != Cat.FLAT && it.cat != Cat.T1_FLAT }
            if (cs.isEmpty()) "–" else pct(passRate(cs, k))
        }
        val fl = cases.filter { it.target == t && (it.cat == Cat.FLAT || it.cat == Cat.T1_FLAT) }
        sb.appendLine("| ${tonesStr(t)} | " + row.joinToString(" | ") + " | ${pct(passRate(fl, k))} |")
    }
    sb.appendLine()
}

/** 不看闸门、只看分数的可分性：AUC 与最优阈值 */
fun thresholdTable(sb: StringBuilder, cases: List<Case>, title: String, ks: List<Int>) {
    val nonT1 = cases.filter { !it.target.all { t -> t == 1 } }
    sb.appendLine("### $title\n")
    sb.appendLine("正例 = 正确读法（含引用式三声），负例 = 读平 + 两字都错。AUC = 随机抽一正一负，正例分数更低的概率。" +
        "最优阈值按 Youden（通关率 + 拦下率 − 1 最大）。\n")
    sb.appendLine("| 修法 | AUC | 0.5 时 正确通关 / 负例拦下 | 最优阈值 | 最优时 正确通关 / 负例拦下 |")
    sb.appendLine("|---|---|---|---|---|")
    for (k in ks) {
        val pos = nonT1.filter { it.cat == Cat.CORRECT || it.cat == Cat.CITATION }.map { it.v[k].score }
        val neg = nonT1.filter { it.cat == Cat.FLAT || it.cat == Cat.WRONG2 }.map { it.v[k].score }
        val auc = auc(pos, neg)
        var best = 0.5f; var bestJ = -1.0
        var t = 0.05f
        while (t < 2f) {
            val j = pos.count { it <= t }.toDouble() / pos.size + neg.count { it > t }.toDouble() / neg.size - 1
            if (j > bestJ) { bestJ = j; best = t }
            t += 0.01f
        }
        fun at(th: Float) = "${pct(pos.count { it <= th }.toDouble() / pos.size)} / ${pct(neg.count { it > th }.toDouble() / neg.size)}"
        sb.appendLine("| ${methods[k].id} ${methods[k].label} | ${f(auc.toFloat())} | ${at(0.5f)} | ${f(best, 2)} | ${at(best)} |")
    }
    sb.appendLine()
}

fun auc(pos: List<Float>, neg: List<Float>): Double {
    val all = (pos.map { it to 1 } + neg.map { it to 0 }).sortedBy { it.first }
    var rankSum = 0.0
    var i = 0
    while (i < all.size) {
        var j = i
        while (j < all.size && all[j].first == all[i].first) j++
        val avg = (i + j + 1) / 2.0
        for (k in i until j) if (all[k].second == 1) rankSum += avg
        i = j
    }
    // 正例分数越低越好：AUC = P(pos < neg)
    val u = rankSum - pos.size * (pos.size + 1) / 2.0
    return 1 - u / (pos.size.toDouble() * neg.size)
}

fun ids(vararg x: String) = x.map { methodIndex(it) }

/** 正确读法与读平的走势跨度（P90−P10 半音）分布，看幅度闸门的余量 */
fun spanTable(sb: StringBuilder, cases: List<Case>, title: String) {
    sb.appendLine("### $title\n")
    sb.appendLine("| 目标 | 正确 P1 / P5 / 中位 | 读平 中位 / P95 / P99 | 正确 < 2 半音 | 正确 < 3 半音 |")
    sb.appendLine("|---|---|---|---|---|")
    fun q(xs: List<Float>, p: Double) = if (xs.isEmpty()) Float.NaN else xs[((xs.size - 1) * p).toInt()]
    for (t in targets.filter { contourGateApplies(it) }) {
        val c = cases.filter { it.target == t && it.cat == Cat.CORRECT }.mapNotNull { it.span }.sorted()
        val fl = cases.filter { it.target == t && it.cat == Cat.FLAT }.mapNotNull { it.span }.sorted()
        if (c.isEmpty()) continue
        sb.appendLine("| ${tonesStr(t)} | ${f(q(c, .01), 1)} / ${f(q(c, .05), 1)} / ${f(q(c, .5), 1)} | " +
            "${f(q(fl, .5), 1)} / ${f(q(fl, .95), 1)} / ${f(q(fl, .99), 1)} | ${pct(c.count { it < 2 }.toDouble() / c.size)} | ${pct(c.count { it < 3 }.toDouble() / c.size)} |")
    }
    sb.appendLine()
}

/** 读平但带一点漂移：漂移多少半音时，归一化就把它拉成满量程的走势 */
fun driftSweep(sb: StringBuilder, refs: Map<List<Int>, Pipeline.Ref>, refName: String, ks: List<Int>) {
    val drifts = listOf(-3f, -2f, -1.5f, -1f, -0.5f, -0.25f, 0f, 0.5f, 1f, 2f)
    sb.appendLine("### 读平 + 漂移扫描（$refName 参照，非全一声词，长度 1× / 2×）\n")
    sb.appendLine("读平（同一音高），整词线性漂移 d 半音（负 = 下滑），帧级抖动照常。格内是通关率（应低）。" +
        "末行是归一化后学习者序列的典型峰峰值。\n")
    sb.appendLine("| 修法 | 长度 | " + drifts.joinToString(" | ") { "${f(it, 2)}" } + " |")
    sb.appendLine("|---|---|" + drifts.joinToString("") { "---|" })
    val res = HashMap<Triple<Int, Float, Float>, Double>()
    val pp = HashMap<Float, MutableList<Float>>()
    for (ratio in listOf(1f, 2f)) for (d in drifts) {
        val cs = ArrayList<Case>(); var s = 5000
        for (t in targets.filter { contourGateApplies(it) }) for (sex in Synth.Sex.values()) for (rep in 0 until 4) {
            val ref = refs[t]!!.norm
            val raw = Synth.track(Synth.Reading(t, flat = true, flatDriftSt = d),
                Synth.Options((ratio * Dtw.voiced(ref).size).toInt(), sex), Random(s++))
            val l = Pipeline.learner(raw) ?: continue
            if (ratio == 1f) Dtw.voiced(l.norm).let { v -> pp.getOrPut(d) { ArrayList() }.add(v.max() - v.min()) }
            cs += Case(t, refName, Cat.FLAT, ratio, sex.name, t, judgeAll(ref, l, t))
        }
        for (k in ks) res[Triple(k, ratio, d)] = passRate(cs, k)
    }
    for (k in ks) for (ratio in listOf(1f, 2f))
        sb.appendLine("| ${methods[k].id} | ${f(ratio, 0)}× | " + drifts.joinToString(" | ") { pct(res[Triple(k, ratio, it)]!!) } + " |")
    sb.appendLine("| 归一化峰峰值 | 1× | " + drifts.joinToString(" | ") { d -> pp[d]!!.sorted().let { f(it[it.size / 2], 2) } } + " |")
    sb.appendLine()
}

// ───────────────────────────── 3. 走势幅度扫描 ─────────────────────────────

fun excursionSweep(sb: StringBuilder, refs: Map<List<Int>, Pipeline.Ref>, refName: String, ks: List<Int>) {
    val es = listOf(0f, 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.8f, 1f)
    sb.appendLine("### 走势幅度扫描（$refName 参照，非全一声词，长度 1× 与 2×）\n")
    sb.appendLine("把正确读法的走势按比例压缩（0 = 读平，1 = 正常）。格内是通关率。")
    sb.appendLine("括号里是该档的典型走势跨度（P90−P10，半音）。\n")
    val rows = ks.associateWith { HashMap<Pair<Float, Float>, Double>() }
    val spans = HashMap<Float, MutableList<Float>>()
    for (ratio in listOf(1f, 2f)) for (e in es) {
        val cs = ArrayList<Case>()
        var s = 1000
        for (t in targets.filter { tg -> tg.any { it in 2..4 } }) for (sex in Synth.Sex.values()) for (rep in 0 until 4) {
            val ref = refs[t]!!.norm
            val raw = Synth.track(Synth.Reading(t, excursion = e), Synth.Options((ratio * Dtw.voiced(ref).size).toInt(), sex), Random(s++))
            val l = Pipeline.learner(raw) ?: continue
            spanSemitones(l.cleaned)?.let { spans.getOrPut(e) { ArrayList() }.add(it) }
            cs += Case(t, refName, Cat.CORRECT, ratio, sex.name, t, judgeAll(ref, l, t))
        }
        for (k in ks) rows[k]!![ratio to e] = passRate(cs, k)
    }
    sb.appendLine("| 修法 | 长度 | " + es.joinToString(" | ") { e -> "${f(e, 1)} (${f(spans[e]!!.sorted()[spans[e]!!.size / 2], 1)})" } + " |")
    sb.appendLine("|---|---|" + es.joinToString("") { "---|" })
    for (k in ks) for (ratio in listOf(1f, 2f))
        sb.appendLine("| ${methods[k].id} | ${f(ratio, 0)}× | " + es.joinToString(" | ") { pct(rows[k]!![ratio to it]!!) } + " |")
    sb.appendLine()
}

// ───────────────────────────── 4. TTS 组（真实音频） ─────────────────────────────

data class Utt(val voice: String, val rate: Int, val word: String, val tones: List<Int>, val kind: String, val l: Pipeline.Learner)

fun loadWords(): List<Pair<String, List<Int>>> =
    File("tts/words.tsv").readLines().filter { it.isNotBlank() && !it.startsWith("#") }
        .map { it.split("\t").let { p -> p[0] to p[1].split(",").map(String::toInt) } }

fun ttsStudy(sb: StringBuilder, refsIdeal: Map<List<Int>, Pipeline.Ref>) {
    val dir = File("build/tts")
    if (!File(dir, "learner").isDirectory) { sb.appendLine("（没有 build/tts，跳过 TTS 组）\n"); return }
    val words = loadWords()
    val toneOf = words.toMap()

    // 参照：Tingting @140 经 ReferenceShaper 整形
    sb.appendLine("## 4. TTS 组（macOS `say` 生成的真实语音音频，走完整 YIN）\n")
    val ttsRefs = words.associate { (w, t) -> w to Pipeline.ttsRef(Pipeline.readWav(File(dir, "ref/Tingting_140_$w.wav")), t) }
    sb.appendLine("参照来源（Tingting 140 wpm，按 App 的整形流程；走向矛盾时回退理想轮廓）：\n")
    sb.appendLine("| 词 | 声调 | 来源 | 参照有声帧 |")
    sb.appendLine("|---|---|---|---|")
    for ((w, t) in words) sb.appendLine("| $w | ${tonesStr(t)} | ${ttsRefs[w]!!.source} | ${Dtw.voiced(ttsRefs[w]!!.norm).size} |")
    sb.appendLine()

    // 学习者侧：原音 + 三种重合成（原 F0 自检 / 读平 / 走势减半）
    val files = File(dir, "learner").listFiles()!!.filter { it.name.endsWith(".wav") }.sortedBy { it.name }
    val utts = files.parallelStream().flatMap { file ->
        val (voice, rate, word) = file.nameWithoutExtension.split("_", limit = 3)
        val tones = toneOf[word] ?: return@flatMap java.util.stream.Stream.empty<Utt>()
        val samples = Pipeline.readWav(file)
        val raw = Pipeline.rawHz(samples)
        val orig = Pipeline.learner(raw) ?: return@flatMap java.util.stream.Stream.empty<Utt>()
        val out = ArrayList<Utt>()
        out += Utt(voice, rate.toInt(), word, tones, "orig", orig)
        val voicedHz = orig.cleaned.filter { it > 0 }.sorted()
        val med = voicedHz[voicedHz.size / 2]
        val rnd = Random(file.name.hashCode())
        fun resynth(kind: String, map: (Int, Float) -> Float) {
            val target = FloatArray(orig.cleaned.size) { k -> if (orig.cleaned[k] > 0) map(k, orig.cleaned[k]) else 0f }
            Pipeline.learner(Pipeline.rawHz(Synth.resynthesize(samples, target)))?.let { out += Utt(voice, rate.toInt(), word, tones, kind, it) }
        }
        resynth("resynth") { _, hz -> hz }
        val nV = orig.cleaned.size
        resynth("flat") { k, _ -> (med * 2.0.pow((-0.8 * k / nV + Synth.gauss(rnd) * 0.1) / 12.0)).toFloat() }
        resynth("half") { _, hz -> (med * 2.0.pow(0.5 * 12 * log2(hz / med) / 12.0)).toFloat() }
        out.stream()
    }.toList()
    sb.appendLine("学习者语音：${utts.count { it.kind == "orig" }} 条原音（9 个中文语音 × 110 / 175 / 260 wpm × ${words.size} 词）；" +
        "另把每条重合成为「原 F0（自检）」「读平」「走势减半」三种。\n")

    val vc = utts.filter { it.kind == "orig" }.map { u -> u.l.cleaned.count { it > 0 } }.sorted()
    sb.appendLine("原音有声帧数：中位 ${vc[vc.size / 2]}，P10 ${vc[vc.size / 10]}；有声帧 < 20 的占 ${pct(vc.count { it < 20 }.toDouble() / vc.size)}。" +
        "macOS 的这些语音在不少音节上周期性很弱（YIN 的 d′ 只到 0.12–0.35，过不了 0.15 阈值），常常只提到一个字的 F0。" +
        "所以下面每张表给两个口径：全部，以及只看有声帧 ≥ 20（约 160 ms，大致两个字都提到了）的。\n")
    for (minV in listOf(5, 20)) for ((refLabel, refFor) in listOf<Pair<String, (String, List<Int>) -> FloatArray>>(
        "TTS 整形参照" to { w, _ -> ttsRefs[w]!!.norm },
        "理想轮廓参照" to { _, t -> refsIdeal[t]!!.norm })) {
        val utts = utts.filter { u -> u.l.cleaned.count { it > 0 } >= minV }
        val cases = ArrayList<Case>()
        val jobs = ArrayList<() -> List<Case>>()
        for ((w, t) in words) {
            val ref = refFor(w, t)
            val m = Dtw.voiced(ref).size
            jobs += {
                val out = ArrayList<Case>()
                for (u in utts) {
                    val ratio = Dtw.voiced(u.l.norm).size.toFloat() / m
                    val cat: Cat? = when (u.kind) {
                        "orig" -> if (u.tones == t) Cat.CORRECT else categorize(t, u.tones)
                        "flat" -> if (u.word == w) (if (t.all { it == 1 }) Cat.T1_FLAT else Cat.FLAT) else null
                        else -> null
                    }
                    if (cat != null) out += Case(t, refLabel, cat, ratio, u.voice, u.tones, judgeAll(ref, u.l, t), u.rate, spanSemitones(u.l.cleaned))
                }
                out
            }
        }
        jobs.parallelStream().map { it() }.toList().forEach { cases += it }
        sb.appendLine("### TTS 组 · $refLabel · 有声帧 ≥ $minV\n")
        sb.appendLine("正确 = 任何一个读出同样声调组合的词；错调 = 其它声调组合的词；读平 = 同一个词的读平重合成。")
        sb.appendLine("长度比 n/m 的分布：正确读法 P10–P90 = ${ratioSpread(cases.filter { it.cat == Cat.CORRECT })}。\n")
        sb.appendLine("| 修法 | 正确 | 读平 拦下 | 错一字 拦下 | 错两字 拦下 | 正确·按语速 110/175/260 | 正确·Tingting 本人 | 一声词：读平通关 / 读错拦下 |")
        sb.appendLine("|---|---|---|---|---|---|---|---|")
        val nonT1 = cases.filter { !it.target.all { x -> x == 1 } }
        val t1 = cases.filter { it.target.all { x -> x == 1 } }
        for (k in methods.indices) {
            val corr = nonT1.filter { it.cat == Cat.CORRECT }
            fun rej(c: Cat) = pct(1 - passRate(nonT1.filter { it.cat == c }, k))
            val byRate = listOf(110, 175, 260).joinToString("/") { r -> pct(passRate(corr.filter { it.rate == r }, k)) }
            sb.appendLine("| ${methods[k].id} ${methods[k].label} | ${pct(passRate(corr, k))} | ${rej(Cat.FLAT)} | ${rej(Cat.WRONG1)} | ${rej(Cat.WRONG2)} | " +
                "$byRate | ${pct(passRate(corr.filter { it.sex == "Tingting" }, k))} | " +
                "${pct(passRate(t1.filter { it.cat.shouldPass }, k))} / ${pct(1 - passRate(t1.filter { !it.cat.shouldPass }, k))} |")
        }
        sb.appendLine()
        thresholdTable(sb, cases, "TTS 组 · $refLabel · 有声帧 ≥ $minV · 分数可分性", (0..8).toList() + ids("Bs2"))
        spanTable(sb, cases, "TTS 组 · $refLabel · 有声帧 ≥ $minV · 走势跨度分布")
    }

    // 自检：重合成原 F0 与原音的分数差
    val diffs = ArrayList<Float>()
    for ((w, t) in words) {
        val ref = ttsRefs[w]!!.norm
        for (u in utts.filter { it.kind == "resynth" && it.word == w }) {
            val o = utts.first { it.kind == "orig" && it.word == w && it.voice == u.voice && it.rate == u.rate }
            diffs += abs(methods[0].score(ref, u.l.norm) - methods[0].score(ref, o.l.norm))
        }
    }
    diffs.sort()
    sb.appendLine("重合成自检：同一词用原 F0 重合成后再提 F0，现行分数与原音之差的中位数 ${f(diffs[diffs.size / 2])}，" +
        "90 分位 ${f(diffs[(diffs.size * 0.9).toInt()])}（说明「读平」重合成里的差别来自 F0，而不是重合成本身）。\n")

    // 走势减半的 TTS
    sb.appendLine("走势减半（同一个词，原音走势按半音压缩一半）：通关率 — " + ids("BASE", "B10", "B20", "BASE+C2", "BASE+C3", "B20n+C2").joinToString("；") { k ->
        val cs = words.filter { (_, t) -> t.any { it in 2..4 } }.flatMap { (w, t) ->
            utts.filter { it.kind == "half" && it.word == w }.map { methods[k].judge(ttsRefs[w]!!.norm, it.l.norm, it.l.cleaned, t).pass }
        }
        "${methods[k].id} ${pct(cs.count { it }.toDouble() / cs.size)}"
    } + "\n")
}

fun ratioSpread(cs: List<Case>): String {
    val r = cs.map { it.ratio }.sorted()
    if (r.isEmpty()) return "–"
    return "${f(r[(r.size * 0.1).toInt()], 2)}–${f(r[(r.size * 0.9).toInt()], 2)}"
}

// ───────────────────────────── 5. 对照用例 ─────────────────────────────

fun goldenCases(sb: StringBuilder) {
    sb.appendLine("## 5. testdata/scoring 对照用例在各修法下的判定\n")
    val names = listOf("t1t1_level_jitter" to listOf(1, 1), "t1t1_male_level" to listOf(1, 1), "t1t1_falling" to listOf(1, 1),
        "t1t1_tts_declining" to listOf(1, 1), "t2t2_rising" to listOf(2, 2), "t4t4_falling" to listOf(4, 4),
        "t4t4_read_flat" to listOf(4, 4), "t3_dipping" to listOf(3), "t2t4_gap" to listOf(2, 4), "t2t2_contradict" to listOf(2, 2))
    sb.appendLine("| 用例 | " + methods.joinToString(" | ") { it.id } + " |")
    sb.appendLine("|---|" + methods.joinToString("") { "---|" })
    for ((n, t) in names) {
        val l = Pipeline.learner(Pipeline.rawHz(Pipeline.readWav(File(repoRoot, "testdata/scoring/$n.wav")))) ?: continue
        val ref = Pipeline.idealRef(t)
        sb.appendLine("| $n | " + methods.joinToString(" | ") { m ->
            val v = m.judge(ref, l.norm, l.cleaned, t); "${f(v.score, 2)}${if (v.gated) "⛔" else if (v.pass) "✓" else "✗"}"
        } + " |")
    }
    sb.appendLine("\n✓ 通关　✗ 分数不通关　⛔ 闸门拦下。参照均为理想轮廓（与 golden.json 的 dtwScore 同口径）。\n")
}

// ───────────────────────────── main ─────────────────────────────

fun main(args: Array<String>) {
    if (args.firstOrNull() == "diag") { diagVoices(); diagDips(); return }
    val only = args.toSet()
    fun want(x: String) = only.isEmpty() || x in only
    val t0 = System.currentTimeMillis()
    val idealRefs = targets.associateWith { Pipeline.Ref(Pipeline.idealRef(it), "ideal") }

    val sb = StringBuilder()
    sb.appendLine("# 评分修法对比实验结果（自动生成）\n")
    sb.appendLine("由 `android/scoring-study` 生成，勿手改。方法编号见 `Methods.kt` 与报告。\n")
    sb.appendLine("方法：" + methods.joinToString("；") { "**${it.id}** ${it.label}" } + "\n")

    if (want("cause")) causeStudy(sb)

    // 合成组：理想轮廓参照 + TTS 整形参照（每个声调组合取 words.tsv 里第一个词）
    val ttsRefs: Map<List<Int>, Pipeline.Ref>? = File("build/tts/ref").takeIf { it.isDirectory }?.let { dir ->
        val words = loadWords()
        targets.associateWith { t ->
            val w = words.first { it.second == t }.first
            Pipeline.ttsRef(Pipeline.readWav(File(dir, "Tingting_140_$w.wav")), t)
        }
    }
    if (want("synth")) {
        sb.appendLine("## 2. 合成测试集\n")
        val reps = 3
        for ((name, refs) in listOfNotNull("理想轮廓参照" to idealRefs, ttsRefs?.let { "TTS 整形参照" to it })) {
            val cases = synthCases(refs, name, reps, 42)
            sb.appendLine("**$name**：${cases.size} 条（${targets.size} 个目标声调组合 × 读法 × 6 档长度 × 男女 × $reps 次随机）。\n")
            summaryTable(sb, cases, "合成 · $name · 总表")
            ratioTable(sb, cases, "合成 · $name · 按长度比（通关率）", ids("V3", "BASE", "A1", "A4", "B0", "B10", "B20", "Bs2", "BASE+C2", "B20n+C2"))
            perTargetFlat(sb, cases, "合成 · $name · 各目标读平通关率", ids("BASE", "B20", "BASE+C2"))
            thresholdTable(sb, cases, "合成 · $name · 分数可分性与阈值", (0..8).toList() + ids("Bs2"))
            confusionTable(sb, cases, "合成 · $name · 现行算法的错调混淆", 0)
            confusionTable(sb, cases, "合成 · $name · B20n+C2 的错调混淆", methodIndex("B20n+C2"))
            spanTable(sb, cases, "合成 · $name · 走势跨度分布")
            excursionSweep(sb, refs, name, ids("BASE", "A4", "B10", "B20", "BASE+C2", "BASE+C3", "BASE+C4", "B20n+C2"))
            driftSweep(sb, refs, name, ids("V3", "BASE", "A1", "A4", "B10", "B20", "BASE+C2", "B20n+C2"))
        }
        if (ttsRefs != null) {
            sb.appendLine("合成组用到的 TTS 参照来源：" + targets.joinToString("；") { "${tonesStr(it)} ${ttsRefs[it]!!.source}" } + "\n")
        }
    }
    if (want("tts")) ttsStudy(sb, idealRefs)
    if (want("golden")) goldenCases(sb)

    val out = File(resultsDir, if (only.isEmpty()) "results.md" else "results-${only.joinToString("-")}.md")
    out.writeText(sb.toString())
    println(sb)
    println("写入 ${out.path}，用时 ${(System.currentTimeMillis() - t0) / 1000} s")
}
