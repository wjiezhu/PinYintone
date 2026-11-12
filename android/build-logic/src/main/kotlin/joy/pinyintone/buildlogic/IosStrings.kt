package joy.pinyintone.buildlogic

/**
 * iOS `Localizable.strings` → Android `strings.xml`。
 *
 * 只转白名单里的键（Android 用到的那些），并在构建时校验：
 * 每个键在每种语言里都要有，且各语言的格式占位符一致——缺译或占位符对不上直接构建失败，
 * 而不是在某个语言里运行时崩溃或显示错。
 */
object IosStrings {

    /** iOS 语言目录 → Android 资源目录。英文作默认（values/） */
    val LANGUAGES = linkedMapOf(
        "en" to "values",
        "zh-Hans" to "values-zh",
        "fr" to "values-fr",
        "ar" to "values-ar",
        "es" to "values-es",
    )


    /** 解析 .strings：`"key" = "value";`，支持 /* */ 与 // 注释、\" \\ \n 转义 */
    fun parse(text: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        var i = 0
        fun skipWsAndComments() {
            while (i < text.length) {
                when {
                    text[i].isWhitespace() -> i++
                    text.startsWith("/*", i) -> { i = text.indexOf("*/", i + 2).let { if (it < 0) text.length else it + 2 } }
                    text.startsWith("//", i) -> { i = text.indexOf('\n', i).let { if (it < 0) text.length else it + 1 } }
                    else -> return
                }
            }
        }
        fun quoted(): String {
            require(text[i] == '"') { "位置 $i 应为引号" }
            i++
            val sb = StringBuilder()
            while (text[i] != '"') {
                if (text[i] == '\\') {
                    i++
                    when (val e = text[i]) {
                        'n' -> sb.append('\n'); 't' -> sb.append('\t'); 'r' -> sb.append('\r')
                        'U', 'u' -> { sb.append(text.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                        else -> sb.append(e)
                    }
                } else sb.append(text[i])
                i++
            }
            i++
            return sb.toString()
        }
        while (true) {
            skipWsAndComments()
            if (i >= text.length) break
            val key = quoted()
            skipWsAndComments(); require(text[i] == '=') { "键 $key 后应为 =" }; i++
            skipWsAndComments()
            val value = quoted()
            skipWsAndComments(); require(text[i] == ';') { "键 $key 的值后应为 ;" }; i++
            out[key] = value
        }
        return out
    }

    private val SPEC = Regex("""%(?:(\d+)\$)?([@dif]|ld|lu|%)""")

    /** 占位符签名（按参数位置排序的类型），用于跨语言比对 */
    fun signature(value: String): List<String> {
        var next = 1
        return SPEC.findAll(value).filter { it.groupValues[2] != "%" }.map { m ->
            val pos = m.groupValues[1].toIntOrNull() ?: next++
            pos to (if (m.groupValues[2] == "@") "s" else "d")
        }.sortedBy { it.first }.map { "${it.first}:${it.second}" }.toList()
    }

    /** iOS 占位符 → Android：%@ → %s；多个参数时一律写成带位置的 %1$s */
    fun convertFormat(value: String): String {
        val args = SPEC.findAll(value).count { it.groupValues[2] != "%" }
        var next = 1
        return SPEC.replace(value) { m ->
            val type = m.groupValues[2]
            if (type == "%") return@replace "%%"
            val pos = m.groupValues[1].toIntOrNull() ?: next++
            val t = if (type == "@") "s" else "d"
            if (args > 1 || m.groupValues[1].isNotEmpty()) "%$pos\$$t" else "%$t"
        }
    }

    /** Android 资源字符串转义 */
    fun escape(value: String): String {
        val sb = StringBuilder()
        for ((idx, c) in value.withIndex()) {
            when {
                c == '&' -> sb.append("&amp;")
                c == '<' -> sb.append("&lt;")
                c == '>' -> sb.append("&gt;")
                c == '\\' -> sb.append("\\\\")
                c == '\'' -> sb.append("\\'")
                c == '"' -> sb.append("\\\"")
                c == '\n' -> sb.append("\\n")
                (c == '@' || c == '?') && idx == 0 -> sb.append('\\').append(c)
                else -> sb.append(c)
            }
        }
        return sb.toString()
    }

    /**
     * 生成全部语言的 strings.xml。返回 Android 资源目录名 → 文件内容。
     * 缺键或占位符不一致时抛错（构建失败），错误信息列出所有问题。
     */
    fun generate(sources: Map<String, String>, keys: List<String>): Map<String, String> {
        val parsed = LANGUAGES.keys.associateWith { lang ->
            parse(sources[lang] ?: error("缺少 $lang.lproj/Localizable.strings"))
        }
        val problems = ArrayList<String>()
        for (key in keys) {
            val sigs = LANGUAGES.keys.mapNotNull { lang ->
                val v = parsed.getValue(lang)[key]
                if (v == null) { problems.add("$lang 缺少键 $key"); null } else lang to signature(v)
            }
            if (sigs.map { it.second }.distinct().size > 1) {
                problems.add("$key 各语言占位符不一致：" + sigs.joinToString { "${it.first}=${it.second}" })
            }
        }
        if (problems.isNotEmpty()) error("iOS 字符串转换失败：\n" + problems.joinToString("\n"))

        return LANGUAGES.entries.associate { (lang, dir) ->
            val strings = parsed.getValue(lang)
            dir to buildString {
                append("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
                append("<!-- 由 iOS 的 $lang.lproj/Localizable.strings 生成，勿手改。键名单见 android/app/ios-strings.keys -->\n")
                append("<resources>\n")
                for (key in keys) {
                    append("    <string name=\"").append(key).append("\">")
                    append(escape(convertFormat(strings.getValue(key))))
                    append("</string>\n")
                }
                append("</resources>\n")
            }
        }
    }

    /** 键名单文件：每行一个键，# 开头为注释 */
    fun parseKeys(text: String): List<String> =
        text.lines().map { it.substringBefore('#').trim() }.filter { it.isNotEmpty() }.distinct()
}
