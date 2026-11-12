package joy.pinyintone.core.theme

import joy.pinyintone.core.RepoFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 对应 iOS `ThemeContrastTests`：普通文字 ≥ 4.5:1，图形元素 ≥ 3:1，浅色与深色都测。
 * 另外核对色值与 Theme.swift 完全相同（两端同一套 token）。
 */
class ThemeTokensTest {
    private val t = ThemeTokens

    private fun check(name: String, fg: ThemeTokens.Pair, bgName: String, bg: ThemeTokens.Pair, min: Double) {
        for ((mode, f, b) in listOf(Triple("浅色", fg.light, bg.light), Triple("深色", fg.dark, bg.dark))) {
            val r = Contrast.ratio(f, b)
            assertTrue("$mode：$name 在 $bgName 上对比度 ${"%.2f".format(r)}:1，低于 $min:1", r >= min)
        }
    }

    private val surfaces = listOf(
        "主背景" to t.background, "次级背景" to t.secondaryBackground, "内容面" to t.surface,
        "声调模块浅底" to t.sageSurface, "送气模块浅底" to t.blueSurface,
    )

    @Test
    fun tokensMatchIosTheme() {
        val swift = RepoFiles.read("PinYintone/Core/UI/Theme.swift")
        val found = Regex("""static let (\w+): Pair = \(0x([0-9A-Fa-f]{6}), 0x([0-9A-Fa-f]{6})\)""")
            .findAll(swift).associate { m ->
                m.groupValues[1] to ThemeTokens.Pair(m.groupValues[2].toInt(16), m.groupValues[3].toInt(16))
            }
        assertEquals("token 集合", found.keys, t.all.keys)
        for ((k, v) in t.all) assertEquals("token $k", found[k], v)
    }

    @Test
    fun textIsReadableOnEverySurface() {
        for ((bgName, bg) in surfaces) {
            check("主文字", t.textPrimary, bgName, bg, 4.5)
            check("次要文字", t.textSecondary, bgName, bg, 4.5)
            check("深松绿文字", t.primary, bgName, bg, 4.5)
        }
    }

    @Test
    fun labelsOnFilledButtonsAreReadable() {
        check("主按钮上的文字", t.onPrimary, "深松绿", t.primary, 4.5)
        check("停止键上的文字", t.onLearnerAccent, "陶红", t.learnerAccent, 4.5)
    }

    @Test
    fun graphicColoursStandOutFromEverySurface() {
        for ((bgName, bg) in surfaces) {
            check("参考曲线", t.primary, bgName, bg, 3.0)
            check("学习者曲线 / 出错图标", t.learnerAccent, bgName, bg, 3.0)
            check("雾蓝点缀", t.blueAccent, bgName, bg, 3.0)
            check("赭（三声标记）", t.ochre, bgName, bg, 3.0)
        }
    }

    @Test
    fun baselineRatiosMatchTheSpecification() {
        assertEquals(8.34, Contrast.ratio(t.primary.light, 0xFFFFFF), 0.06)
        assertEquals(4.65, Contrast.ratio(t.learnerAccent.light, 0xFFFFFF), 0.06)
        assertEquals(4.66, Contrast.ratio(t.blueAccent.light, 0xFFFFFF), 0.06)
    }

    @Test
    fun theTwoCurvesDifferByLineStyleNotOnlyColour() {
        assertNotEquals(t.primary.light, t.learnerAccent.light)
        assertNotEquals(t.primary.dark, t.learnerAccent.dark)
        assertTrue("参考曲线是实线", ThemeTokens.Curve.referenceDash.isEmpty())
        assertFalse("学习者曲线是虚线", ThemeTokens.Curve.learnerDash.isEmpty())
    }
}
