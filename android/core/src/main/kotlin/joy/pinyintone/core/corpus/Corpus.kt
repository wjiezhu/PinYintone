package joy.pinyintone.core.corpus

import joy.pinyintone.core.json.Json
import joy.pinyintone.core.json.ints
import joy.pinyintone.core.json.list
import joy.pinyintone.core.json.obj
import joy.pinyintone.core.json.str

/** 词条类别：决定归属哪个关卡。对应 Swift `LexemeCategory`。 */
enum class LexemeCategory(val rawValue: String) {
    ASPIRATION("aspiration"),  // 关卡 1：送气对立
    TONE("tone");              // 关卡 2：声调

    companion object {
        fun of(raw: String?): LexemeCategory? = entries.firstOrNull { it.rawValue == raw }
    }
}

/**
 * 词集标签。取消 A/B 后只保留在语料与历史记录里，**不影响出题顺序或反馈**（CLAUDE.md）。
 * 对应 Swift `WordSet`。
 */
enum class WordSet(val rawValue: String) {
    SET1("set1"), SET2("set2"), ASSESSMENT("assessment");

    companion object {
        fun of(raw: String?): WordSet? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 对应 Swift `Lexeme`。字段名与 lexemes.json 一致。 */
data class Lexeme(
    val id: String,
    val hanzi: String,
    val pinyin: String,
    val tones: List<Int>,
    val category: LexemeCategory,
    val focus: String,
    val french: String,
    val darija: String,
    /** 母语者参照录音文件名；目前全部为 null（用理想轮廓） */
    val audioFilename: String?,
    val wordSet: WordSet?,
) {
    /**
     * 按界面语言取释义：阿拉伯语界面优先 Darija，其余优先法语，另一种作第二行。
     * 没有的语言**不现编**。对应 Swift `Lexeme.glosses(for:)`。
     */
    fun glosses(language: String): Pair<String, String?> {
        val (a, b) = if (language == "ar") darija to french else french to darija
        val primary = a.ifEmpty { b }
        val secondary = if (a.isEmpty() || b.isEmpty()) null else b
        return primary to secondary
    }
}

/**
 * 语料：读 iOS 与 Android 共用的 `PinYintone/Resources/Corpus/lexemes.json`（不另存一份）。
 * 对应 Swift `CorpusLoader` 的取词部分；游标（练习位置）由调用方保存，见 `PracticeStore`。
 */
class Corpus(val lexemes: List<Lexeme>) {

    fun lexeme(id: String): Lexeme? = lexemes.firstOrNull { it.id == id }

    /** 指定类别的推进顺序：声调为固定词序（[TONE_ORDER]），未列入的按 JSON 原序追加在后 */
    fun orderedPool(category: LexemeCategory): List<Lexeme> {
        val pool = lexemes.filter { it.category == category }
        if (category != LexemeCategory.TONE) return pool
        val remaining = pool.toMutableList()
        val ordered = ArrayList<Lexeme>()
        for (id in TONE_ORDER) {
            val i = remaining.indexOfFirst { it.id == id }
            if (i >= 0) ordered.add(remaining.removeAt(i))
        }
        return ordered + remaining
    }

    /** 自测词（原「固定测试词集」），沿用固定词序。对应 `assessmentPool()` */
    fun assessmentPool(): List<Lexeme> =
        orderedPool(LexemeCategory.TONE).filter { it.wordSet == WordSet.ASSESSMENT }

    companion object {
        /**
         * 关卡 2 固定词序（由易到难）。**与 Swift `CorpusLoader.toneOrder` 必须相同**——
         * `CorpusTest` 直接解析那个 Swift 文件比对，改一边另一边会红。
         */
        val TONE_ORDER = listOf(
            "yisheng", "canjia",
            "xiuxi", "qingchu",
            "xiangxin",
            "heshui", "shenti", "jingli",
            "zaocan",
            "ziji",
            "xianzai", "dianshi", "sushe", "hanzi",
        )

        fun parse(json: String): Corpus = Corpus(Json.parse(json).list().mapNotNull { raw ->
            val o = raw.obj()
            val category = LexemeCategory.of(o["category"].str()) ?: return@mapNotNull null
            Lexeme(
                id = o["id"].str()!!,
                hanzi = o["hanzi"].str()!!,
                pinyin = o["pinyin"].str()!!,
                tones = o["tones"].ints(),
                category = category,
                focus = o["focus"].str() ?: "",
                french = o["french"].str() ?: "",
                darija = o["darija"].str() ?: "",
                audioFilename = o["audioFilename"].str()?.takeIf { it.isNotEmpty() },
                wordSet = WordSet.of(o["wordSet"].str()),
            )
        })
    }
}
