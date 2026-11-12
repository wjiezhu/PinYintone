package joy.pinyintone.buildlogic

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class IosStringsTest {

    private val repo = File(System.getProperty("pinyintone.repoRoot") ?: "../..")

    @Test
    fun parsesStringsFile() {
        val m = IosStrings.parse(
            """
            /* 注释 */
            // 行注释
            "a" = "He said \"hi\"\nnext";
            "b"="100%";
            """.trimIndent(),
        )
        assertEquals("He said \"hi\"\nnext", m["a"])
        assertEquals("100%", m["b"])
    }

    @Test
    fun convertsFormatSpecifiers() {
        assertEquals("Word %1\$d of %2\$d", IosStrings.convertFormat("Word %1\$d of %2\$d"))
        assertEquals("Hello %s", IosStrings.convertFormat("Hello %@"))
        assertEquals("%1\$d: %2\$s", IosStrings.convertFormat("%d: %@"))
        assertEquals("%2\$s %1\$d", IosStrings.convertFormat("%2\$@ %1\$d"))
        assertEquals(listOf("1:d", "2:s"), IosStrings.signature("%2\$@ %1\$d"))
    }

    @Test
    fun escapesForAndroid() {
        assertEquals("l\\'eau \\\"x\\\" &amp; &lt;b&gt;\\n", IosStrings.escape("l'eau \"x\" & <b>\n"))
        assertEquals("\\@home", IosStrings.escape("@home"))
    }

    @Test
    fun rejectsMissingKeysAndMismatchedPlaceholders() {
        val ok = "\"k\" = \"%d words\";"
        val sources = IosStrings.LANGUAGES.keys.associateWith { ok }.toMutableMap()
        sources["fr"] = "\"k\" = \"%@ mots\";"
        sources["ar"] = ""
        try {
            IosStrings.generate(sources, listOf("k"))
            fail("应构建失败")
        } catch (e: IllegalStateException) {
            assertTrue(e.message!!.contains("ar 缺少键 k"))
            assertTrue(e.message!!.contains("占位符不一致"))
        }
    }

    /** 真实的 iOS 字符串 + Android 的键名单：能生成、五种语言齐全 */
    @Test
    fun realLocalizationsConvertCleanly() {
        val dir = File(repo, "PinYintone/Resources/Localizations")
        val sources = IosStrings.LANGUAGES.keys.associateWith { File(dir, "$it.lproj/Localizable.strings").readText() }
        val keys = IosStrings.parseKeys(File(repo, "android/app/ios-strings.keys").readText())
        val out = IosStrings.generate(sources, keys)
        assertEquals(setOf("values", "values-zh", "values-fr", "values-ar", "values-es"), out.keys)
        assertTrue(out.getValue("values-zh").contains("<string name=\"stage2_title\">声调练习</string>"))
        assertTrue(out.getValue("values").contains("Word %1\$d of %2\$d"))
        assertTrue(out.getValue("values-es").contains("Palabra %1\$d de %2\$d"))
    }
}
