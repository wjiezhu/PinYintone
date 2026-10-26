package joy.pinyintone.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import joy.pinyintone.core.practice.FeedbackStyle
import joy.pinyintone.core.practice.PracticeStore
import joy.pinyintone.core.practice.RecordSink
import joy.pinyintone.core.practice.TrainingRecord
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * 声调记录（普通练习与自测）。列与 iOS 上报的 `TrainingSessionDTO` 一一对应，
 * 外加 `synced`（本阶段不做上传，恒为 false，等上传做好后由同步逻辑置位）。
 */
@Entity(tableName = "training_records")
data class TrainingRecordEntity(
    @PrimaryKey val id: String,
    val deviceID: String,
    val classCode: String?,
    val role: String,
    val groupAssignment: String,
    val lexemeID: String,
    val dtwScore: Double,
    val grade: String,
    val attemptNumber: Int,
    val timestampMillis: Long,
    val referenceType: String?,
    val voicedFrameCount: Int,
    val qualityFlag: Boolean,
    val referenceSwitchedDuringAttempt: Boolean,
    val phase: String?,
    val wordSetID: String?,
    val presentationOrder: String?,
    val assessmentSetVersion: String?,
    val feedbackMode: String?,
    val resultStatus: String?,
    val failureReason: String?,
    val schemaVersion: Int,
    val appVersion: String,
    val synced: Boolean,
    /** v7 起：走势跨度（半音）；技术失败或无法计算为 null。见 [TrainingRecord.pitchSpanSemitones] */
    val pitchSpanSemitones: Double? = null,
    /** v7 起："android"。数据库版本 1 的旧行由迁移补成 "android"（本端只会产生本端的记录） */
    val platform: String = "android",
) {
    fun toRecord() = TrainingRecord(
        id, deviceID, classCode, role, groupAssignment, lexemeID, dtwScore, grade, attemptNumber,
        timestampMillis, referenceType, voicedFrameCount, qualityFlag, referenceSwitchedDuringAttempt,
        phase, wordSetID, presentationOrder, assessmentSetVersion, feedbackMode, resultStatus,
        failureReason, schemaVersion, appVersion,
        pitchSpanSemitones = pitchSpanSemitones, platform = platform, synced = synced,
    )

    companion object {
        fun of(r: TrainingRecord) = TrainingRecordEntity(
            r.id, r.deviceID, r.classCode, r.role, r.groupAssignment, r.lexemeID, r.dtwScore, r.grade,
            r.attemptNumber, r.timestampMillis, r.referenceType, r.voicedFrameCount, r.qualityFlag,
            r.referenceSwitchedDuringAttempt, r.phase, r.wordSetID, r.presentationOrder,
            r.assessmentSetVersion, r.feedbackMode, r.resultStatus, r.failureReason, r.schemaVersion,
            r.appVersion, r.synced, r.pitchSpanSemitones, r.platform,
        )
    }
}

@Dao
interface TrainingRecordDao {
    @Insert
    suspend fun insert(record: TrainingRecordEntity)

    /** 待上传（上传逻辑以后接；失败保持 false，下次启动重试） */
    @Query("SELECT * FROM training_records WHERE synced = 0 ORDER BY timestampMillis")
    suspend fun unsynced(): List<TrainingRecordEntity>

    @Query("UPDATE training_records SET synced = 1 WHERE id IN (:ids)")
    suspend fun markSynced(ids: List<String>)

    /** 诊断页：最近一次录音的技术信息（不取词条、分数等内容） */
    @Query("SELECT voicedFrameCount, resultStatus, failureReason, timestampMillis FROM training_records " +
        "ORDER BY timestampMillis DESC LIMIT 1")
    suspend fun latestAttempt(): LatestAttempt?
}

data class LatestAttempt(
    val voicedFrameCount: Int,
    val resultStatus: String?,
    val failureReason: String?,
    val timestampMillis: Long,
)

@Database(entities = [TrainingRecordEntity::class], version = 2, exportSchema = false)
abstract class AppDatabase : RoomDatabase() {
    abstract fun records(): TrainingRecordDao

    companion object {
        /**
         * 1 → 2（记录 schemaVersion 7）：加走势跨度与 platform 两列。旧行保持原样：
         * 跨度为 NULL（当时没算），platform 补 "android"。不用破坏性重建——那会丢掉未上传的记录。
         */
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE training_records ADD COLUMN pitchSpanSemitones REAL")
                db.execSQL("ALTER TABLE training_records ADD COLUMN platform TEXT NOT NULL DEFAULT 'android'")
            }
        }

        fun open(context: Context): AppDatabase =
            Room.databaseBuilder(context, AppDatabase::class.java, "pinyintone.db")
                .addMigrations(MIGRATION_1_2)
                .build()
    }
}

/** 记录落库：在应用级作用域里异步写，页面关掉也写得完 */
class RoomRecordSink(private val dao: TrainingRecordDao, private val scope: CoroutineScope) : RecordSink {
    override fun save(record: TrainingRecord) {
        scope.launch { dao.insert(TrainingRecordEntity.of(record)) }
    }
}

/** 练习位置、按词尝试次数、显示模式偏好、是否问过麦克风权限 */
class PrefsPracticeStore(private val prefs: SharedPreferences) : PracticeStore {

    override fun attempts(lexemeID: String): Int = prefs.getInt(ATTEMPTS + lexemeID, 0)

    override fun incrementAttempts(lexemeID: String): Int {
        val next = attempts(lexemeID) + 1
        prefs.edit().putInt(ATTEMPTS + lexemeID, next).apply()
        return next
    }

    override var practiceCursor: Int
        get() = prefs.getInt(CURSOR, 0)
        set(value) { prefs.edit().putInt(CURSOR, value).apply() }

    /** 显示模式：学习者自选，默认动态曲线。**不是实验条件** */
    var feedbackStyle: FeedbackStyle
        get() = FeedbackStyle.of(prefs.getString(STYLE, null))
        set(value) { prefs.edit().putString(STYLE, value.rawValue).apply() }

    /** 是否已经弹过系统的麦克风授权框（用来区分「还没问过」与「被永久拒绝」） */
    var micPermissionRequested: Boolean
        get() = prefs.getBoolean(MIC_ASKED, false)
        set(value) { prefs.edit().putBoolean(MIC_ASKED, value).apply() }

    /** 最近一次成功启动录音时的输入采样率与音源（诊断页用；没录过为 0 / null） */
    var lastInputSampleRate: Int
        get() = prefs.getInt(LAST_RATE, 0)
        set(value) { prefs.edit().putInt(LAST_RATE, value).apply() }
    var lastAudioSource: String?
        get() = prefs.getString(LAST_SOURCE, null)
        set(value) { prefs.edit().putString(LAST_SOURCE, value).apply() }

    /** 学习者关掉过提示的那个新版本号（只对可选更新生效） */
    var dismissedUpdateVersionCode: Int
        get() = prefs.getInt(DISMISSED_UPDATE, 0)
        set(value) { prefs.edit().putInt(DISMISSED_UPDATE, value).apply() }

    private companion object {
        const val LAST_RATE = "diag_last_input_sample_rate"
        const val LAST_SOURCE = "diag_last_audio_source"
        const val DISMISSED_UPDATE = "update_dismissed_version_code"
        // 键名沿用 iOS 的 UserDefaults 键，方便对照
        const val ATTEMPTS = "pt_tone_attempts."
        const val CURSOR = "pt_tone_practice_cursor"
        const val STYLE = "pt_feedback_style"
        const val MIC_ASKED = "mic_permission_requested"
    }
}
