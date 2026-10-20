package joy.pinyintone.core.corpus

import joy.pinyintone.core.RepoFiles
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CorpusTest {

    private val corpus = Corpus.parse(RepoFiles.read("PinYintone/Resources/Corpus/lexemes.json"))

    @Test
    fun readsSharedCorpus() {
        val tone = corpus.orderedPool(LexemeCategory.TONE)
        assertEquals(14, tone.size)
        assertEquals(6, corpus.orderedPool(LexemeCategory.ASPIRATION).size)
        assertEquals("yisheng", tone.first().id)
        assertEquals(listOf(1, 1), tone.first().tones)
        // 目前没有母语者录音：参照全部用理想轮廓
        assertTrue(corpus.lexemes.all { it.audioFilename == null })
        assertEquals(listOf("xiangxin", "heshui", "sushe", "hanzi"), corpus.assessmentPool().map { it.id })
    }

    /** 固定词序与 Swift `CorpusLoader.toneOrder` 逐项相同 */
    @Test
    fun toneOrderMatchesSwift() {
        val swift = RepoFiles.read("PinYintone/Core/Corpus/CorpusLoader.swift")
        val block = Regex("""toneOrder: \[String] = \[(.*?)]""", RegexOption.DOT_MATCHES_ALL)
            .find(swift)!!.groupValues[1]
        val ids = Regex("\"([a-z]+)\"").findAll(block).map { it.groupValues[1] }.toList()
        assertEquals(ids, Corpus.TONE_ORDER)
    }

    @Test
    fun glossesFollowInterfaceLanguage() {
        val l = corpus.lexeme("yisheng")!!
        assertEquals("Médecin" to "Tbib (طبيب)", l.glosses("fr"))
        assertEquals("Tbib (طبيب)" to "Médecin", l.glosses("ar"))
        assertNull(l.copy(darija = "").glosses("zh").second)
    }
}
