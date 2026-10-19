package joy.pinyintone.core.audio

import kotlin.math.pow
import kotlin.math.sin

/**
 * 理想四声 F0 轮廓合成（Hz 量级）。声调训练与自由文本练习共用。
 * 形态参数与依据见 Swift 版注释（Xu 1997；Howie 1976；Chao 1968）。
 *
 * 对应 Swift：`PinYintone/Core/Audio/ToneContour.swift`。
 * 运算顺序与 Swift 一致；`pow` / `sin` 在 Kotlin 里经 Double 计算再转 Float，
 * 与 Apple 的 `powf` / `sinf` 偶有 1 ulp 之差。
 */
object ToneContour {

    /**
     * 生成给定声调序列的理想 F0 轮廓。
     * @param tones 1–4 为四声，5 为轻声，其它视为 mid。
     * @param perSyllable 每个音节采样的帧数（默认 24，对应 ~768ms @128 帧移）。
     */
    fun ideal(tones: List<Int>, perSyllable: Int = 24): FloatArray {
        val out = FloatArray(tones.size * perSyllable)
        var p = 0
        for (tone in tones) {
            for (i in 0 until perSyllable) {
                val t = i.toFloat() / maxOf(perSyllable - 1, 1).toFloat()
                out[p++] = hzAt(tone, t)
            }
        }
        return out
    }

    private fun hzAt(tone: Int, t: Float): Float = when (tone) {
        // T1 高平：起 270，末段轻微下倾至 258
        1 -> 270f - 12f * t * t
        // T2 阳平：0–30% 走 175→160，30–100% 加速升至 248
        2 -> if (t < 0.30f) {
            val u = t / 0.30f
            175f - 15f * u
        } else {
            val u = (t - 0.30f) / 0.70f
            160f + 88f * u.pow(1.4f)
        }
        // T3 上声（213）：0–55% 减速下降到谷底 95，55–100% 加速回升到 228
        3 -> if (t < 0.55f) {
            val u = t / 0.55f
            175f - 80f * u.pow(1.3f)
        } else {
            val u = (t - 0.55f) / 0.45f
            95f + 133f * u.pow(1.6f)
        }
        // T4 去声 51：前段急降后段趋缓
        4 -> 285f - 145f * t.pow(0.55f)
        // 轻声：短促中平
        5 -> 195f + 6f * sin(t * 6.28f)
        else -> 200f
    }
}
