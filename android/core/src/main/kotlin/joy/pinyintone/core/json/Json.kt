package joy.pinyintone.core.json

/**
 * 极简 JSON 解析器（core 不引第三方库，JSON 库也不引）。语料读取与对照测试共用。
 * 数字保留原文 [Num]，按需转 Int / Float——Float 直接从十进制原文解析，
 * 不经 Double 中转，避免二次舍入。
 */
object Json {

    data class Num(val raw: String) {
        fun toFloat(): Float = raw.toFloat()
        fun toInt(): Int = raw.toInt()
    }

    fun parse(text: String): Any? {
        val p = Parser(text)
        val v = p.value()
        p.ws()
        require(p.i == text.length) { "JSON 末尾有多余内容 @${p.i}" }
        return v
    }

    private class Parser(val s: String) {
        var i = 0

        fun ws() { while (i < s.length && s[i].isWhitespace()) i++ }

        fun value(): Any? {
            ws()
            return when (val c = s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c.isDigit()) num() else error("意外字符 '$c' @$i")
            }
        }

        fun lit(word: String, v: Any?): Any? {
            require(s.startsWith(word, i)) { "期望 $word @$i" }
            i += word.length
            return v
        }

        fun num(): Num {
            val start = i
            while (i < s.length && (s[i].isDigit() || s[i] in "+-.eE")) i++
            return Num(s.substring(start, i))
        }

        fun str(): String {
            i++ // "
            val sb = StringBuilder()
            while (s[i] != '"') {
                if (s[i] == '\\') {
                    i++
                    when (val e = s[i]) {
                        'n' -> sb.append('\n'); 't' -> sb.append('\t'); 'r' -> sb.append('\r')
                        'u' -> { sb.append(s.substring(i + 1, i + 5).toInt(16).toChar()); i += 4 }
                        else -> sb.append(e)
                    }
                } else sb.append(s[i])
                i++
            }
            i++
            return sb.toString()
        }

        fun arr(): List<Any?> {
            i++
            val out = ArrayList<Any?>()
            ws()
            if (s[i] == ']') { i++; return out }
            while (true) {
                out.add(value()); ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == ']') { "期望 ] @$i" }; i++
                return out
            }
        }

        fun obj(): Map<String, Any?> {
            i++
            val out = LinkedHashMap<String, Any?>()
            ws()
            if (s[i] == '}') { i++; return out }
            while (true) {
                ws(); val k = str(); ws()
                require(s[i] == ':') { "期望 : @$i" }; i++
                out[k] = value(); ws()
                if (s[i] == ',') { i++; continue }
                require(s[i] == '}') { "期望 } @$i" }; i++
                return out
            }
        }
    }
}

@Suppress("UNCHECKED_CAST")
fun Any?.obj(): Map<String, Any?> = this as Map<String, Any?>
@Suppress("UNCHECKED_CAST")
fun Any?.list(): List<Any?> = this as List<Any?>
fun Any?.f(): Float = (this as Json.Num).toFloat()
fun Any?.i(): Int = (this as Json.Num).toInt()
fun Any?.floats(): FloatArray = list().let { l -> FloatArray(l.size) { l[it].f() } }
fun Any?.ints(): List<Int> = list().map { it.i() }
fun Any?.str(): String? = this as String?

/** 把字符串写成 JSON 字符串字面量 */
fun jsonString(s: String): String {
    val sb = StringBuilder("\"")
    for (c in s) when {
        c == '"' -> sb.append("\\\"")
        c == '\\' -> sb.append("\\\\")
        c == '\n' -> sb.append("\\n")
        c == '\r' -> sb.append("\\r")
        c == '\t' -> sb.append("\\t")
        c < ' ' -> sb.append("\\u%04x".format(c.code))
        else -> sb.append(c)
    }
    return sb.append('"').toString()
}
