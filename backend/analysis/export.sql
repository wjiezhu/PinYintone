-- Pinyintone 实验数据导出 / 统计（PostgreSQL / Neon）
--
-- ⚠ 设计变更：**已取消 A/B 分组**。训练阶段有两种反馈呈现方式
--   （颜色块 / 动态 F0 曲线），由学习者自己在设置里切换，不再有随机分组。
--   · schema_version >= 3：feedback_mode = 学习者**自己选**的显示模式
--     （颜色块 / 音高曲线），presentation_order 为空，group_assignment 恒为 'n/a'。
--     ⚠ 自选不是随机分配：**不要**拿 feedback_mode 做组间比较，会有自选择偏差
--     （倾向选曲线的人本来可能就更投入）。它只能用来描述"当时屏幕上是什么"。
--   · schema_version < 3 或为空的历史记录：可能带 staticColor / dynamicF0，
--     那是取消分组之前受试内 A/B 阶段的数据，**与新数据不可直接合并比较**。
--   · users.experiment_group、users.counterbalance_index 为历史列，已停止写入。
--   · word_set_id：set1 / set2 现已合并为单一训练池，标签仅作历史标记；
--     assessment = 固定测试词集，与训练词条不重叠。
--   · presentation_order 同上，仅历史记录有值。
--   · phase：pretest / training / posttest。旧记录该列为 NULL（升级前数据）。
--
-- ⚠ 结果解释边界（升级需求 §1）：以下所有指标都是**应用日志指标**
--   （DTW 距离、通关率、触发率），不是语言能力等级，不得直接当作声调习得证据。
--
-- 用法：
--   · Neon 控制台 SQL Editor 里逐段运行，右上角可「Download as CSV」。
--   · 或本地 psql：psql "<NEON_DATABASE_URL>" -c "\copy (这里粘贴某段 SELECT) TO 'out.csv' WITH CSV HEADER"
--
-- 质量约定：
--   · 技术性失败（没录上）**现在会入库**，标记为 result_status = 'technical_retry'，
--     并带 failure_reason（匿名原因）。这类行**没有发音成绩**：dtw_score = -1、
--     grade = 'n/a' 是哨兵值，只为占住非空列。
--     ⚠ **任何算分数的查询都必须先筛掉它们**，否则 -1 会被当成满分拉低均值。
--     本文件各段已统一加 `COALESCE(result_status, 'valid_result') <> 'technical_retry'`
--     （历史行该列为 NULL，用 COALESCE 保住）。想统计失败率见第 4 段。
--   · quality_flag = true 表示异常高 DTW（疑似录音/参照问题），各段默认已剔除；
--     想看全量把 `AND NOT COALESCE(quality_flag, false)` 去掉即可。
--   · reference_switched 理论上恒为 false，出现 true 说明"所见≠所评"，见第 8 段自查。


-- =====================================================================
-- 1) 原始声调记录（长表，每次尝试一行）—— 喂 R / 混合模型 / 学习曲线
-- =====================================================================
SELECT
    device_id,
    class_code,                              -- 学生恒为 NULL（未绑定班级池）
    phase,                                   -- pretest / training / posttest
    word_set_id,                             -- set1 / set2（同一训练池）/ assessment
    assessment_set_version,                  -- 仅测试词集有值
    schema_version,                          -- ≥3：feedback_mode 为自选值（非实验条件）
    app_version,
    feedback_mode,                           -- v3：自选显示模式（不可做组间比较）
    presentation_order,                      -- 同上
    lexeme_id,
    attempt_number,
    dtw_score,                               -- technical_retry 行为 -1 哨兵，非真实分
    -- 哨兵 -1 也满足 <= 0.5，必须显式排除，否则技术失败会被算成"通关"
    CASE WHEN COALESCE(result_status, 'valid_result') = 'technical_retry'
         THEN NULL ELSE (dtw_score <= 0.5) END  AS passed,   -- 通关线 DTW ≤ 0.5
    grade,
    reference_type,                          -- real / tts / ideal
    voiced_frame_count,
    quality_flag,
    result_status,                           -- valid_result / quality_flagged / technical_retry
    failure_reason,                          -- 仅 technical_retry 有值（匿名原因）
    reference_switched,
    timestamp
FROM training_sessions
ORDER BY device_id, phase, word_set_id, lexeme_id, attempt_number, timestamp;


-- =====================================================================
-- 2) 原始送气记录（长表）——按阶段筛选
-- =====================================================================
SELECT
    device_id,
    class_code,
    phase,
    target_word,
    trigger_rate,                            -- 0–1，触发率
    passed,                                  -- 触发率 ≥ 0.6
    timestamp
FROM aspiration_attempts
ORDER BY device_id, timestamp;


-- =====================================================================
-- 3) ★ 前测 vs 后测（固定测试词集，裸测无反馈）
--    同一份 assessment_set_version 内才可比较。
-- =====================================================================
WITH assessment AS (
    SELECT device_id, phase, assessment_set_version, lexeme_id, dtw_score
    FROM training_sessions
    WHERE phase IN ('pretest', 'posttest')
      AND word_set_id = 'assessment'
      AND NOT COALESCE(quality_flag, false)
      -- 必须排除：technical_retry 的 dtw_score = -1，会把均值拉低成假"进步"
      AND COALESCE(result_status, 'valid_result') <> 'technical_retry' 
)
SELECT
    device_id,
    assessment_set_version,
    COUNT(*) FILTER (WHERE phase = 'pretest')                      AS n_pretest,
    COUNT(*) FILTER (WHERE phase = 'posttest')                     AS n_posttest,
    ROUND(AVG(dtw_score) FILTER (WHERE phase = 'pretest')::numeric, 4)   AS mean_dtw_pre,
    ROUND(AVG(dtw_score) FILTER (WHERE phase = 'posttest')::numeric, 4)  AS mean_dtw_post,
    ROUND((AVG(dtw_score) FILTER (WHERE phase = 'pretest')
         - AVG(dtw_score) FILTER (WHERE phase = 'posttest'))::numeric, 4)
                                                                   AS dtw_improvement
    -- 正值 = 后测 DTW 更低 = 与参照更接近（应用日志指标，非能力等级）
FROM assessment
GROUP BY device_id, assessment_set_version
ORDER BY device_id;


-- =====================================================================
-- 4) 数据质量自查（升级需求 §1.2：区分发音问题 / 录音问题 / 系统问题）
-- =====================================================================
SELECT
    phase,
    COUNT(*)                                                        AS n_records,
    COUNT(*) FILTER (WHERE COALESCE(quality_flag, false))           AS n_quality_flagged,
    -- 技术性失败：分母含它们，看"录音有多难成"；算成绩时务必筛掉
    COUNT(*) FILTER (WHERE result_status = 'technical_retry')       AS n_technical_retry,
    ROUND(100.0 * COUNT(*) FILTER (WHERE result_status = 'technical_retry')
          / NULLIF(COUNT(*), 0), 1)                                 AS pct_technical_retry,
    COUNT(*) FILTER (WHERE failure_reason = 'permission_denied')    AS n_fail_permission,
    COUNT(*) FILTER (WHERE failure_reason = 'insufficient_voiced_frames') AS n_fail_no_voice,
    COUNT(*) FILTER (WHERE failure_reason = 'recording_interrupted') AS n_fail_interrupted,
    COUNT(*) FILTER (WHERE failure_reason = 'low_signal_quality')   AS n_fail_low_signal,
    COUNT(*) FILTER (WHERE COALESCE(reference_switched, false))     AS n_reference_switched,
    -- ↑ 应恒为 0；非 0 说明参照锁定失效，这批记录"所见 ≠ 所评"，需剔除
    ROUND(AVG(voiced_frame_count) FILTER (
        WHERE COALESCE(result_status, 'valid_result') <> 'technical_retry'
    )::numeric, 1)                                                  AS mean_voiced_frames,
    COUNT(*) FILTER (WHERE reference_type = 'real')                 AS n_ref_real,
    COUNT(*) FILTER (WHERE reference_type = 'tts')                  AS n_ref_tts,
    COUNT(*) FILTER (WHERE reference_type = 'ideal')                AS n_ref_ideal,
    COUNT(*) FILTER (WHERE phase IS NULL)                           AS n_legacy_no_phase
FROM training_sessions
GROUP BY phase
ORDER BY phase NULLS LAST;
