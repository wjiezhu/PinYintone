package joy.pinyintone.core.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdateTest {

    private val published = """
        {"platform":"android","published":true,"latestVersionCode":3,"latestVersionName":"0.3.0",
         "minSupportedVersionCode":2,"downloadUrl":"https://example.org/pinyintone.apk",
         "releaseNotes":{"zh":"修复录音","fr":"Correctifs"}}
    """.trimIndent()

    private val release = AppUpdate.parse(published)!!

    @Test fun parsesBackendResponse() {
        assertEquals(3, release.latestVersionCode)
        assertEquals("0.3.0", release.latestVersionName)
        assertEquals(2, release.minSupportedVersionCode)
        assertEquals("https://example.org/pinyintone.apk", release.downloadUrl)
        assertEquals("Correctifs", release.notesFor("fr"))
        // 没有阿拉伯语说明：先退 en（也没有），再退 zh
        assertEquals("修复录音", release.notesFor("ar"))
    }

    @Test fun unpublishedOrGarbageMeansNoPrompt() {
        assertNull(AppUpdate.parse("""{"platform":"android","published":false,"latestVersionCode":null,
            "minSupportedVersionCode":null,"downloadUrl":null,"releaseNotes":{}}"""))
        assertNull(AppUpdate.parse("<html>502 Bad Gateway</html>"))
        assertNull(AppUpdate.parse(""))
        assertNull(AppUpdate.parse("""{"published":true,"latestVersionCode":3}"""))
    }

    @Test fun onlyHttpsLinksAreAccepted() {
        for (bad in listOf("http://example.org/a.apk", "javascript:alert(1)", "file:///sdcard/a.apk",
                           "intent://x#Intent;end", "https://", "https:// evil")) {
            assertNull(bad, AppUpdate.parse(published.replace("https://example.org/pinyintone.apk", bad)))
        }
        assertTrue(AppUpdate.isHttps("HTTPS://example.org"))
    }

    @Test fun decision() {
        assertEquals(AppUpdate.Prompt.Required(release), AppUpdate.decide(1, release, dismissedVersionCode = 0))
        // 必须更新的提示关不掉：关过也照样提示
        assertEquals(AppUpdate.Prompt.Required(release), AppUpdate.decide(1, release, dismissedVersionCode = 3))
        assertEquals(AppUpdate.Prompt.Optional(release), AppUpdate.decide(2, release, dismissedVersionCode = 0))
        // 关掉的是这个版本：不再提示；出了更新的版本再提示
        assertNull(AppUpdate.decide(2, release, dismissedVersionCode = 3))
        assertEquals(AppUpdate.Prompt.Optional(release), AppUpdate.decide(2, release, dismissedVersionCode = 2))
        assertNull(AppUpdate.decide(3, release, 0))
        assertNull(AppUpdate.decide(4, release, 0))
        assertNull(AppUpdate.decide(1, null, 0))
    }

    @Test fun minNeverAboveLatest() {
        val r = AppUpdate.parse(published.replace("\"minSupportedVersionCode\":2", "\"minSupportedVersionCode\":9"))!!
        assertEquals(3, r.minSupportedVersionCode)
        assertNull(AppUpdate.decide(3, r, 0))
    }
}
