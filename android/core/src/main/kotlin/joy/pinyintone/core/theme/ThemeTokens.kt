package joy.pinyintone.core.theme

/**
 * 界面颜色的语义 token（需求 2.3 版 U01），浅色 / 深色各一套。
 * **色值与 iOS `Theme.Hex` 完全相同**——`ThemeTokensTest` 解析 Theme.swift 逐个核对，改一边另一边会红。
 * 页面里不写色值，只用这里的 token（CLAUDE.md 禁令 24）。
 *
 * 放在 core（纯 JVM）而不是 app：对比度测试不需要 Android SDK 就能跑。
 */
object ThemeTokens {
    data class Pair(val light: Int, val dark: Int)

    val background = Pair(0xFFFFFF, 0x111514)
    val secondaryBackground = Pair(0xF5F7F6, 0x181D1B)
    /** 次级背景之上的内容面 */
    val surface = Pair(0xFFFFFF, 0x1D2321)
    val textPrimary = Pair(0x202623, 0xECEFED)
    val textSecondary = Pair(0x626B66, 0xA9B2AD)
    /** 深松绿：主按钮、选中状态、参考曲线（实线） */
    val primary = Pair(0x245743, 0x7CC4A3)
    val onPrimary = Pair(0xFFFFFF, 0x0C1A14)
    /** 陶红：学习者曲线（虚线）、录音停止态、出错图标 */
    val learnerAccent = Pair(0xB35B4C, 0xE8A193)
    val onLearnerAccent = Pair(0xFFFFFF, 0x2A0F0A)
    /** 雾蓝：只作点缀 */
    val blueAccent = Pair(0x5C7889, 0x9DB8C8)
    val sageSurface = Pair(0xEDF3EE, 0x1A2921)
    val blueSurface = Pair(0xEEF2F5, 0x1A242B)
    /** 分隔线。**不能当小字颜色用** */
    val border = Pair(0xE1E6E3, 0x2C3431)
    /** 颜色模式里三声用的赭色 */
    val ochre = Pair(0x86672D, 0xD6B36A)

    /** 出错图标沿用陶红；提示**文字**一律用主文字色（陶红在浅色底上不够 4.5:1） */
    val warning = learnerAccent

    /** 全部 token（名字与 Swift `Theme.Hex` 的成员名相同） */
    val all: Map<String, Pair> = linkedMapOf(
        "background" to background, "secondaryBackground" to secondaryBackground,
        "surface" to surface, "textPrimary" to textPrimary, "textSecondary" to textSecondary,
        "primary" to primary, "onPrimary" to onPrimary, "learnerAccent" to learnerAccent,
        "onLearnerAccent" to onLearnerAccent, "blueAccent" to blueAccent,
        "sageSurface" to sageSurface, "blueSurface" to blueSurface, "border" to border, "ochre" to ochre,
    )

    /** 颜色模式每个声调的颜色（对应 Swift `Theme.toneColor`）。颜色不是唯一通道：另有形状、调号、调类名 */
    fun toneColor(tone: Int): Pair = when (tone) {
        1 -> primary
        2 -> blueAccent
        3 -> ochre
        4 -> learnerAccent
        else -> textSecondary
    }

    /**
     * 两条曲线的线型。参考实线、学习者虚线——**线型是颜色之外的第二个区分通道**（禁令 25）。
     * 单位与 iOS 相同（pt ≈ dp）。
     */
    object Curve {
        val referenceDash: FloatArray = floatArrayOf()
        val learnerDash: FloatArray = floatArrayOf(8f, 6f)
        const val REFERENCE_WIDTH = 2.5f
        const val LEARNER_WIDTH = 2.5f
    }

    /** 间距与尺寸（dp），与 iOS `Theme.Space` 等相同 */
    object Size {
        const val XS = 4
        const val S = 8
        const val M = 12
        const val L = 16
        const val XL = 24
        const val PAGE_MARGIN = 20
        const val RADIUS = 6
        const val MIN_TAP = 48          // Android 的最小触控建议是 48dp（iOS 44pt）
        const val RECORD_BUTTON = 72
        const val CHART_HEIGHT = 220
    }
}

/** WCAG 2.x 相对亮度与对比度。对应 `ThemeContrastTests.swift` 里的同名计算 */
object Contrast {
    fun luminance(rgb: Int): Double {
        fun channel(v: Int): Double {
            val c = v / 255.0
            return if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((rgb shr 16) and 0xFF) + 0.7152 * channel((rgb shr 8) and 0xFF) +
            0.0722 * channel(rgb and 0xFF)
    }

    fun ratio(a: Int, b: Int): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }
}
