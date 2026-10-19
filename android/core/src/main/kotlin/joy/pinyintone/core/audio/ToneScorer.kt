package joy.pinyintone.core.audio

/**
 * 一次声调录音的评分流程（平台无关部分）：
 * clean → 有声帧数检查 → normalize → DTW → 平调词走向闸门 → grade。
 *
 * 对应 Swift：`ToneTrainingViewModel.stopRecordingAndEvaluate()` 里的计算部分
 * （iOS 那边与界面、入库写在一起，没有独立的类）。两边要一起改。
 *
 * 普通练习与自测用的是同一套计算；差别只在呈现（CLAUDE.md），所以这里不区分。
 */
class ToneScorer(
    private val f0Extractor: F0Extractor = F0Extractor(),
    private val dtwAnalyzer: DTWAnalyzer = DTWAnalyzer(),
) {

    /** `resultStatus`，与 iOS / 后端的原始值一致 */
    enum class ResultStatus(val rawValue: String) {
        VALID_RESULT("valid_result"),
        TECHNICAL_RETRY("technical_retry"),
        QUALITY_FLAGGED("quality_flagged"),
    }

    sealed class Outcome {
        /** cleaned 后的原始 Hz 轨迹（闸门用的就是它） */
        abstract val cleanedHz: FloatArray
        abstract val voicedFrames: Int
        abstract val resultStatus: ResultStatus

        /**
         * 技术性失败（有声帧不足）：不生成分数与等级，**不得**计入发音成绩（CLAUDE.md 禁令 9）。
         * 旧业务表入库时由调用方写哨兵 `dtwScore = -1`、`grade = "n/a"`；研究表写 NULL。
         */
        data class TechnicalRetry(
            override val cleanedHz: FloatArray,
            override val voicedFrames: Int,
        ) : Outcome() {
            override val resultStatus get() = ResultStatus.TECHNICAL_RETRY
        }

        data class Scored(
            override val cleanedHz: FloatArray,
            override val voicedFrames: Int,
            val normalized: FloatArray,
            val dtwScore: Float,
            /** 是否被平调词走向闸门拦下；为 true 时 grade 恒为 FAIL，即便 dtwScore ≤ 0.5 */
            val levelToneDropped: Boolean,
            val grade: FeedbackGrade,
            val segmentScores: FloatArray,
        ) : Outcome() {
            val passed: Boolean get() = grade != FeedbackGrade.FAIL
            override val resultStatus
                get() = if (dtwScore >= QUALITY_FLAG_THRESHOLD) ResultStatus.QUALITY_FLAGGED
                        else ResultStatus.VALID_RESULT
        }
    }

    /**
     * @param rawHz 录音期间逐帧 [F0Extractor.extract] 的结果（未 clean）
     * @param reference 归一化后的参照（理想轮廓 / 真人录音 / TTS，见 [ReferenceShaper]）
     * @param tones 目标声调；决定闸门是否生效与分段数
     */
    fun evaluate(rawHz: FloatArray, reference: FloatArray, tones: List<Int>): Outcome {
        val cleaned = f0Extractor.clean(rawHz)
        val voicedFrames = cleaned.count { it != 0f }
        if (voicedFrames < MIN_VOICED_FRAMES) return Outcome.TechnicalRetry(cleaned, voicedFrames)

        val normalized = f0Extractor.normalize(cleaned)
        val score = dtwAnalyzer.distance(reference, normalized)
        // iOS 在这里还会拦 NaN / Infinity（按分析失败处理）。distance 的输出是有限值，
        // 防御留给调用方，与 iOS 一致地按技术失败处理。

        // 闸门必须喂原始 Hz 的 cleaned，不能喂 normalized（CLAUDE.md 禁令 15）
        val dropped = ToneDirectionGate.fails(cleaned, tones)
        val grade = if (dropped) FeedbackGrade.FAIL else dtwAnalyzer.grade(score)
        val segments = if (tones.isEmpty()) FloatArray(0)
                       else dtwAnalyzer.segmentScores(reference, normalized, tones.size)
        return Outcome.Scored(cleaned, voicedFrames, normalized, score, dropped, grade, segments)
    }

    /** 理想轮廓参照（iOS 进词时的即时占位，也是兜底） */
    fun idealReference(tones: List<Int>): FloatArray = f0Extractor.normalize(ToneContour.ideal(tones))

    companion object {
        /** 有声帧少于此数 = 没录上（技术失败）。Swift: `minVoicedFrames` */
        const val MIN_VOICED_FRAMES: Int = 5

        /** DTW ≥ 此值标记 quality_flagged。Swift: `qualityFlagThreshold` */
        const val QUALITY_FLAG_THRESHOLD: Float = 2.0f
    }
}
