-- Pinyintone 实验数据导出 / 统计（PostgreSQL / Neon）
-- 分组：staticColor = 组 A（静态色块），dynamicF0 = 组 B（动态 F0）。
-- 用法：
--   · Neon 控制台 SQL Editor 里逐段运行，右上角可「Download as CSV」。
--   · 或本地 psql：psql "<NEON_DATABASE_URL>" -c "\copy (这里粘贴某段 SELECT) TO 'out.csv' WITH CSV HEADER"
-- 说明：
--   · 分组由后端注册时均衡随机分配，存于 users.experiment_group 与
--     training_sessions.group_assignment（最权威），按名字 nickname 对回个人。
--   · 声调数据 training_sessions 自带 group_assignment。
--   · 送气数据 aspiration_attempts 无分组列 → 先 join users.experiment_group，
--     缺失时回退到该设备在 training_sessions 里的分组。
--   · 只取正式两组，排除教师 n/a 与异常。


-- =====================================================================
-- 1) 原始声调记录（长表，每次尝试一行）—— 喂 R/混合模型/学习曲线
-- =====================================================================
SELECT
    device_id,
    class_code,
    group_assignment,                       -- staticColor=A / dynamicF0=B
    lexeme_id,
    attempt_number,
    dtw_score,
    (dtw_score <= 0.5)            AS passed, -- 通关线 DTW≤0.5
    grade,
    timestamp
FROM training_sessions
WHERE group_assignment IN ('staticColor', 'dynamicF0')
ORDER BY device_id, lexeme_id, attempt_number, timestamp;


-- =====================================================================
-- 2) 原始送气记录（长表，每次尝试一行）
-- =====================================================================
SELECT
    a.device_id,
    a.class_code,
    COALESCE(
        u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
    )                               AS group_assignment,
    a.target_word,
    a.trigger_rate,                          -- 0–1，触发率
    a.passed,                                -- 触发率≥0.6
    a.timestamp
FROM aspiration_attempts a
LEFT JOIN users u ON u.device_id = a.device_id
WHERE COALESCE(
        u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
      ) IN ('staticColor', 'dynamicF0')
ORDER BY a.device_id, a.timestamp;


-- =====================================================================
-- 3) 每被试 · 声调汇总（每人一行）—— 受试间分析用
-- =====================================================================
WITH t AS (
    SELECT
        device_id,
        group_assignment,
        dtw_score,
        attempt_number,
        ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY timestamp DESC) AS rn_desc
    FROM training_sessions
    WHERE group_assignment IN ('staticColor', 'dynamicF0')
)
SELECT
    device_id,
    group_assignment,
    COUNT(*)                                              AS n_attempts,
    ROUND(AVG(dtw_score)::numeric, 4)                     AS mean_dtw,
    ROUND(STDDEV_SAMP(dtw_score)::numeric, 4)             AS sd_dtw,
    ROUND(MIN(dtw_score)::numeric, 4)                     AS best_dtw,
    ROUND(AVG(dtw_score) FILTER (WHERE rn_desc <= 5)::numeric, 4) AS mean_dtw_last5,
    ROUND(AVG((dtw_score <= 0.5)::int)::numeric, 4)       AS pass_rate
FROM t
GROUP BY device_id, group_assignment
ORDER BY group_assignment, device_id;


-- =====================================================================
-- 4) 每被试 · 送气汇总（每人一行）
-- =====================================================================
SELECT
    a.device_id,
    COALESCE(u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
    )                                                     AS group_assignment,
    COUNT(*)                                              AS n_attempts,
    ROUND(AVG(a.trigger_rate)::numeric, 4)                AS mean_trigger_rate,
    ROUND(STDDEV_SAMP(a.trigger_rate)::numeric, 4)        AS sd_trigger_rate,
    ROUND(AVG(a.passed::int)::numeric, 4)                 AS pass_rate
FROM aspiration_attempts a
LEFT JOIN users u ON u.device_id = a.device_id
GROUP BY a.device_id, 2
HAVING COALESCE(u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
      ) IN ('staticColor', 'dynamicF0')
ORDER BY group_assignment, a.device_id;


-- =====================================================================
-- 5) 每被试 · 声调+送气合并（每人一行）★ 受试间 t 检验 / ANCOVA 主表
-- =====================================================================
WITH tone AS (
    SELECT device_id, group_assignment,
           AVG(dtw_score) AS mean_dtw,
           AVG((dtw_score <= 0.5)::int) AS tone_pass_rate,
           COUNT(*) AS tone_n
    FROM training_sessions
    WHERE group_assignment IN ('staticColor', 'dynamicF0')
    GROUP BY device_id, group_assignment
),
asp AS (
    SELECT a.device_id,
           AVG(a.trigger_rate) AS mean_trigger,
           AVG(a.passed::int)  AS asp_pass_rate,
           COUNT(*) AS asp_n
    FROM aspiration_attempts a
    GROUP BY a.device_id
)
SELECT
    COALESCE(tone.device_id, asp.device_id)               AS device_id,
    tone.group_assignment,
    tone.tone_n,
    ROUND(tone.mean_dtw::numeric, 4)                      AS mean_dtw,
    ROUND(tone.tone_pass_rate::numeric, 4)                AS tone_pass_rate,
    asp.asp_n,
    ROUND(asp.mean_trigger::numeric, 4)                   AS mean_trigger_rate,
    ROUND(asp.asp_pass_rate::numeric, 4)                  AS asp_pass_rate
FROM tone
FULL OUTER JOIN asp ON asp.device_id = tone.device_id
WHERE tone.group_assignment IN ('staticColor', 'dynamicF0')
ORDER BY tone.group_assignment, device_id;


-- =====================================================================
-- 6) 组别描述统计（直接看 A/B 差异）
-- =====================================================================
-- 6a 声调
SELECT
    group_assignment,
    COUNT(DISTINCT device_id)                             AS n_participants,
    COUNT(*)                                              AS n_attempts,
    ROUND(AVG(dtw_score)::numeric, 4)                     AS mean_dtw,
    ROUND(STDDEV_SAMP(dtw_score)::numeric, 4)             AS sd_dtw,
    ROUND(AVG((dtw_score <= 0.5)::int)::numeric, 4)       AS pass_rate
FROM training_sessions
WHERE group_assignment IN ('staticColor', 'dynamicF0')
GROUP BY group_assignment;

-- 6b 送气
SELECT
    COALESCE(u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
    )                                                     AS group_assignment,
    COUNT(DISTINCT a.device_id)                           AS n_participants,
    COUNT(*)                                              AS n_attempts,
    ROUND(AVG(a.trigger_rate)::numeric, 4)                AS mean_trigger_rate,
    ROUND(AVG(a.passed::int)::numeric, 4)                 AS pass_rate
FROM aspiration_attempts a
LEFT JOIN users u ON u.device_id = a.device_id
GROUP BY 1
HAVING COALESCE(u.experiment_group,
        (SELECT ts.group_assignment FROM training_sessions ts WHERE ts.device_id = a.device_id LIMIT 1)
      ) IN ('staticColor', 'dynamicF0');


-- =====================================================================
-- 7) 学习增益：每被试每词 首次 vs 末次 DTW（前后测/学习曲线）
-- =====================================================================
WITH ranked AS (
    SELECT
        device_id, group_assignment, lexeme_id, dtw_score,
        ROW_NUMBER() OVER (PARTITION BY device_id, lexeme_id ORDER BY attempt_number, timestamp)        AS rn_first,
        ROW_NUMBER() OVER (PARTITION BY device_id, lexeme_id ORDER BY attempt_number DESC, timestamp DESC) AS rn_last
    FROM training_sessions
    WHERE group_assignment IN ('staticColor', 'dynamicF0')
)
SELECT
    device_id, group_assignment, lexeme_id,
    MAX(dtw_score) FILTER (WHERE rn_first = 1)            AS first_dtw,
    MAX(dtw_score) FILTER (WHERE rn_last = 1)             AS last_dtw,
    ROUND((MAX(dtw_score) FILTER (WHERE rn_first = 1)
         - MAX(dtw_score) FILTER (WHERE rn_last = 1))::numeric, 4) AS dtw_improvement  -- 正值=进步（DTW 下降）
FROM ranked
GROUP BY device_id, group_assignment, lexeme_id
ORDER BY group_assignment, device_id, lexeme_id;
