package joy.pinyintone.app

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import joy.pinyintone.app.data.AppDatabase
import joy.pinyintone.app.data.PrefsPracticeStore
import joy.pinyintone.app.data.RoomRecordSink
import joy.pinyintone.app.update.UpdateChecker
import joy.pinyintone.core.corpus.Corpus
import joy.pinyintone.core.practice.RecordContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import java.util.UUID

/** 进程级依赖。没有 DI 框架：零第三方依赖（CLAUDE.md 禁令 5） */
class PinyintoneApp : Application() {

    /** 落库等不随页面消失的后台工作 */
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val prefs: SharedPreferences by lazy { getSharedPreferences("pinyintone", Context.MODE_PRIVATE) }

    /** 两端共用的语料（构建时从 PinYintone/Resources/Corpus 复制进 assets） */
    val corpus: Corpus by lazy {
        Corpus.parse(assets.open("lexemes.json").bufferedReader(Charsets.UTF_8).use { it.readText() })
    }

    val database: AppDatabase by lazy { AppDatabase.open(this) }

    val practiceStore by lazy { PrefsPracticeStore(prefs) }

    /** 启动时查一次新版本（失败静默） */
    val updates by lazy { UpdateChecker(practiceStore, appScope) }

    val recordSink by lazy { RoomRecordSink(database.records(), appScope) }

    /**
     * 写进旧业务表 `deviceID` 的本机编号（每次安装一个）。只用于旧表兼容，
     * **不是研究身份**——研究身份按账号（CLAUDE.md 禁令 22），登录做好后另接。
     */
    val deviceID: String by lazy {
        prefs.getString(KEY_DEVICE_ID, null) ?: UUID.randomUUID().toString().also {
            prefs.edit().putString(KEY_DEVICE_ID, it).apply()
        }
    }

    val recordContext by lazy {
        RecordContext(deviceID = deviceID, appVersion = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
    }

    private companion object {
        const val KEY_DEVICE_ID = "device_id"
    }
}
