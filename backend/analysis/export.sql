-- Pinyintone 实验数据导出 / 统计（PostgreSQL / Neon）
--
-- ⚠ 设计变更：**已取消 A/B 分组**。训练阶段唯一的反馈呈现方式是
--   动态 F0 可视化（目标轨迹 + 学习者轨迹），不再有条件对比。
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
--   · 技术性失败（有声帧过少）在客户端就不入库，所以这里的每一行都是"录到了"的尝试。
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
    schema_version,                          -- ≥3：动态曲线唯一呈现方式（A/B 已取消）
    app_version,
    feedback_mode,                           -- v3：自选显示模式（不可做组间比较）
    presentation_order,                      -- 同上
    lexeme_id,
    attempt_number,
    dtw_score,
    (dtw_score <= 0.5)    AS passed,         -- 通关线 DTW ≤ 0.5
    grade,
    reference_type,                          -- real / tts / ideal
    voiced_frame_count,
    quality_flag,
    result_status,                           -- valid_result / quality_flagged
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
    COUNT(*) FILTER (WHERE COALESCE(reference_switched, false))     AS n_reference_switched,
    -- ↑ 应恒为 0；非 0 说明参照锁定失效，这批记录"所见 ≠ 所评"，需剔除
    ROUND(AVG(voiced_frame_count)::numeric, 1)                      AS mean_voiced_frames,
    COUNT(*) FILTER (WHERE reference_type = 'real')                 AS n_ref_real,
    COUNT(*) FILTER (WHERE reference_type = 'tts')                  AS n_ref_tts,
    COUNT(*) FILTER (WHERE reference_type = 'ideal')                AS n_ref_ideal,
    COUNT(*) FILTER (WHERE phase IS NULL)                           AS n_legacy_no_phase
FROM training_sessions
GROUP BY phase
ORDER BY phase NULLS LAST;
