package joy.pinyintone.app.update

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.net.toUri
import joy.pinyintone.app.BuildConfig
import joy.pinyintone.app.data.PrefsPracticeStore
import joy.pinyintone.core.update.AppUpdate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.net.HttpURLConnection
import java.net.URL

/**
 * 启动时查一次有没有新版本（`GET {API_BASE_URL}/api/app-version/android`）。
 *
 * 网络不通、超时、后端没配好、响应看不懂——一律静默跳过，不打扰练习。
 * 有新版本时 [prompt] 给出提示；下载链接交给系统浏览器，**App 内不下载、不安装安装包**。
 * 不带任何身份信息：只是一个匿名 GET。
 */
class UpdateChecker(private val store: PrefsPracticeStore, private val scope: CoroutineScope) {

    private val _prompt = MutableStateFlow<AppUpdate.Prompt?>(null)
    val prompt: StateFlow<AppUpdate.Prompt?> = _prompt

    /** 最近一次检查的结果（诊断页用）：尚未检查 / 成功 / 失败 */
    @Volatile var lastCheck: String = "not_checked"
        private set

    private var started = false

    fun checkOnce() {
        if (started) return
        started = true
        scope.launch {
            val body = runCatching { fetch("${BuildConfig.API_BASE_URL}/api/app-version/android") }.getOrNull()
            if (body == null) { lastCheck = "failed"; return@launch }
            val release = AppUpdate.parse(body)
            lastCheck = if (release == null) "ok_no_release" else "ok_latest_${release.latestVersionCode}"
            _prompt.value = AppUpdate.decide(BuildConfig.VERSION_CODE, release, store.dismissedUpdateVersionCode)
        }
    }

    /** 关掉可选更新的提示：这个版本不再提示。必须更新的提示关不掉 */
    fun dismiss() {
        val p = _prompt.value as? AppUpdate.Prompt.Optional ?: return
        store.dismissedUpdateVersionCode = p.release.latestVersionCode
        _prompt.value = null
    }

    private fun fetch(url: String): String? {
        val conn = URL(url).openConnection() as HttpURLConnection
        return try {
            conn.connectTimeout = TIMEOUT_MS
            conn.readTimeout = TIMEOUT_MS
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Accept", "application/json")
            if (conn.responseCode != 200) return null
            conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
        } finally {
            conn.disconnect()
        }
    }

    companion object {
        // Render 免费实例冷启动要几十秒；查不到就算了，下次启动再查
        private const val TIMEOUT_MS = 15_000

        /** 用系统浏览器打开下载地址。只放行 https；打不开就返回 false，由界面如实说明 */
        fun openInBrowser(context: Context, url: String): Boolean {
            if (!AppUpdate.isHttps(url)) return false
            val intent = Intent(Intent.ACTION_VIEW, url.toUri())
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return try { context.startActivity(intent); true } catch (_: ActivityNotFoundException) { false }
        }
    }
}
