package joy.pinyintone.study

import java.io.File

/** 诊断：每个 TTS 语音的有声帧数、走势跨度、逐帧 F0 */
fun diagVoices() {
    val files = File("build/tts/learner").listFiles()!!.filter { it.name.endsWith(".wav") }
    val byVoice = files.groupBy { it.name.substringBefore("_") }
    for ((v, fs) in byVoice.toSortedMap()) {
        val stats = fs.mapNotNull { f ->
            val samples = Pipeline.readWav(f)
            val raw = Pipeline.rawHz(samples)
            val l = Pipeline.learner(raw) ?: return@mapNotNull null
            Triple(samples.size / 16000f, l.cleaned.count { it > 0 }, spanSemitones(l.cleaned) ?: 0f)
        }
        val dur = stats.map { it.first }.average(); val vf = stats.map { it.second }.sorted(); val sp = stats.map { it.third }.sorted()
        println("$v n=${stats.size}/${fs.size} 时长 ${f(dur.toFloat(), 2)}s 有声帧 中位 ${vf[vf.size / 2]} P10 ${vf[vf.size / 10]}  跨度 中位 ${f(sp[sp.size / 2], 1)} P10 ${f(sp[sp.size / 10], 1)}")
    }
    for (name in listOf("Tingting_175_学校", "Eddy_175_学校", "Reed_175_现在", "Grandpa_175_现在", "Tingting_175_现在")) {
        val f = File("build/tts/learner/$name.wav"); if (!f.exists()) continue
        val l = Pipeline.learner(Pipeline.rawHz(Pipeline.readWav(f)))
        println("$name: " + l?.cleaned?.joinToString(" ") { if (it == 0f) "." else it.toInt().toString() })
    }
    val r = File("build/tts/ref/Tingting_140_现在.wav")
    println("ref 现在: " + Pipeline.learner(Pipeline.rawHz(Pipeline.readWav(r)))!!.cleaned.joinToString(" ") { if (it == 0f) "." else it.toInt().toString() })
}

/** 诊断用 YIN（阈值可调，仅用于判断漏检的帧是不是「有周期但没过 0.15」） */
fun yinMinDip(frame: FloatArray): Float {
    val n = frame.size; val half = n / 2
    val d = FloatArray(half)
    for (tau in 1 until half) { var s = 0.0; for (i in 0 until n - tau) { val x = frame[i + tau] - frame[i]; s += x * x }; d[tau] = s.toFloat() }
    var run = 0f; var best = 1f
    for (tau in 1 until half) { run += d[tau]; val dn = if (run > 0) d[tau] * tau / run else 1f; if (tau in 32..213) best = minOf(best, dn) }
    return best
}

fun diagDips() {
    for (name in listOf("Tingting_175_学校", "Eddy_175_学校", "Reed_175_现在")) {
        val s = Pipeline.readWav(File("build/tts/learner/$name.wav"))
        val frames = joy.pinyintone.core.audio.AudioFramer.frames(s)
        val rms = frames.map { fr -> kotlin.math.sqrt(fr.map { it * it }.average()).toFloat() }
        val loud = rms.max() * 0.1f
        println("$name 最小 d' (仅响度 > 峰值 10% 的帧): " + frames.indices.filter { rms[it] > loud }.joinToString(" ") { f(yinMinDip(frames[it]), 2) })
    }
}
