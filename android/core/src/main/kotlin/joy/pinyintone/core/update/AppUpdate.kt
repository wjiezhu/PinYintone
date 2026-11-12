package joy.pinyintone.core.update

import joy.pinyintone.core.json.Json

/**
 * 新版本检查的判定（Android 直接分发，不经应用商店）。后端 `GET /api/app-version/android`
 * 返回最新版本号、最低支持版本号、下载地址与各语言的更新说明；这里只做纯计算，网络在 App 里。
 *
 * - 低于最低支持版本 → [Prompt.Required]：提示必须更新（提示不能关，但**不拦练习**——
 *   CLAUDE.md 禁令 19：不设「先完成某事才能练习」的门槛）
 * - 低于最新版本 → [Prompt.Optional]：可以关闭；关掉的那个版本不再提示
 * - 其余（含没发布、响应看不懂、地址不是 https）→ 不提示。检查失败一律静默
 */
object AppUpdate {

    data class Release(
        val latestVersionCode: Int,
        val latestVersionName: String,
        val minSupportedVersionCode: Int,
        val downloadUrl: String,
        val releaseNotes: Map<String, String>,
    ) {
        /** 按界面语言取更新说明，缺的依次退到 en、zh、任意一条 */
        fun notesFor(language: String): String? =
            releaseNotes[language] ?: releaseNotes["en"] ?: releaseNotes["zh"] ?: releaseNotes.values.firstOrNull()
    }

    sealed interface Prompt {
        val release: Release
        data class Optional(override val release: Release) : Prompt
        data class Required(override val release: Release) : Prompt
    }

    /** 解析后端响应；没发布或看不懂时返回 null（不抛异常：检查失败不得打扰练习） */
    fun parse(body: String): Release? {
        val root = runCatching { Json.parse(body) }.getOrNull() as? Map<*, *> ?: return null
        if (root["published"] != true) return null
        val latest = (root["latestVersionCode"] as? Json.Num)?.let { runCatching { it.toInt() }.getOrNull() } ?: return null
        val min = (root["minSupportedVersionCode"] as? Json.Num)?.let { runCatching { it.toInt() }.getOrNull() } ?: 0
        val url = (root["downloadUrl"] as? String)?.trim() ?: return null
        if (!isHttps(url) || latest <= 0) return null
        val name = (root["latestVersionName"] as? String)?.takeIf { it.isNotBlank() } ?: latest.toString()
        val notes = (root["releaseNotes"] as? Map<*, *>).orEmpty()
            .mapNotNull { (k, v) -> if (k is String && v is String && v.isNotBlank()) k to v.trim() else null }
            .toMap()
        return Release(latest, name, minOf(min, latest), url, notes)
    }

    /**
     * @param dismissedVersionCode 学习者关掉过提示的那个最新版本号（只对可选更新生效）
     */
    fun decide(currentVersionCode: Int, release: Release?, dismissedVersionCode: Int): Prompt? = when {
        release == null -> null
        currentVersionCode < release.minSupportedVersionCode -> Prompt.Required(release)
        currentVersionCode < release.latestVersionCode && dismissedVersionCode != release.latestVersionCode ->
            Prompt.Optional(release)
        else -> null
    }

    /** 只把 https 地址交给系统浏览器（App 内不下载、不安装） */
    fun isHttps(url: String): Boolean {
        val u = url.trim()
        if (!u.startsWith("https://", ignoreCase = true)) return false
        val host = u.substring("https://".length).substringBefore('/').substringBefore('?').substringBefore('#')
        return host.isNotEmpty() && host.none { it.isWhitespace() }
    }
}
