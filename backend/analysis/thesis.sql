-- PinYintone 论文取数（PostgreSQL / Neon）—— 旧业务表：练习日志
--
-- 这份文件给什么：
--   0) 设备对照表（只给自己看）      1) 参与者概况            2) 声调长表（每次尝试一行）
--   3) 按声调组合汇总                4) 按词汇总              5) 重复练习曲线
--   6) 每日使用情况                  7) 技术失败与数据质量    8) 送气练习
--   9) 自由文本（9a 按人 / 9b 按词）  10) 自测
--
-- 怎么用：
--   · Neon 控制台 → SQL Editor。**一次只复制一段**（两条 ==== 分隔线之间），
--     运行后点结果右上角 Download → CSV。每段都自带同一份清洗规则，可以单独运行。
--   · 只读：本文件只有 SELECT，不建表、不改数据。
--   · 时间：库里的 timestamp 是 UTC；local_* 列已换成摩洛哥时间（Africa/Casablanca）。
--
-- 每段开头有两个参数，**所有段要改成一样**。最省事：先在本机用文本编辑器打开本文件，
--   「查找并替换」一次改全部，再一段一段复制到 Neon：
--   【参数 1】release_at：2.0 在 App Store 正式上架的时间（UTC）。
--            schema_version >= 6 的记录在这之前只可能来自开发测试和你自己的 TestFlight，
--            一律排除。默认值 2026-10-14 只是占位——**上架后改成真实时间**。
--   【参数 2】excluded_devices：要排除的设备号。默认是三个测试用的假设备号；
--            上架后你若还用自己的手机练过，先跑第 0 段找到自己的 device_id，加进来，例如
--            VALUES ('device-test'), ('sim'), ('dev'), ('你的设备号')
--   另外固定排除：教师账号（role = 'teacher'）。
--
-- 参与者：同一 Apple 账号的多台设备合并为一人（users.account_id）；没有账号编号的旧设备按设备算。
--   编号 P001、P002… 按首次使用时间排；同一份数据重跑编号不变，排除规则改了编号会跟着变。
--   ⚠ 一台设备先后登录过两个账号时，旧业务表分不清这台设备上哪条记录是谁的，会算到后登录的人名下。
--
-- 取数口径（与 CLAUDE.md、RESEARCH_RUNBOOK.md 一致）：
--   · 通过与否一律看 grade（passed 列），不要用 dtw_score <= 0.5 重算：
--     schema_version >= 5 起，全一声的词掉调超过 3 个半音会被走向闸门判不通过（gated_level_tone）。
--   · 技术失败（result_status = 'technical_retry'）没有成绩：长表里 dtw_score / passed 留空，
--     汇总段一律不计入；失败率见第 7 段。质量标记（quality_flagged）同样不进汇总。
--   · 含一声的词：schema_version <= 3 与 >= 4 的分数语义不同，不能混在一起。
--     comparable_across_versions = false 的就是这类旧记录；汇总段把它们单独成行或剔除。
--   · feedback_mode 与自测都是学习者自选的：只能描述，**不能**做组间比较，也不是前后测。
--   · 分数、通过率、触发率是练习反馈与应用日志指标，**不是**语言能力等级。
--   · 新版研究数据（research_* 表）不在这里，用 backend/scripts/export_research.py 导出。


-- =====================================================================
-- 0) 设备对照表 —— 只给你自己看，不要放进论文或附录
-- 用途：找出你自己的设备和测试设备，填进【参数 2】；把昵称对上匿名编号。
-- participant 为空 = 这台设备的记录全部被排除了。n_prerelease_v6 = 会被【参数 1】排除的条数。
-- non_standard_id = 设备号不是正常的 UUID 格式（多半是测试数据）。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
raw AS (
    SELECT device_id, 'tone' AS src, timestamp, schema_version, app_version FROM training_sessions
    UNION ALL SELECT device_id, 'aspiration', timestamp, schema_version, app_version FROM aspiration_attempts
    UNION ALL SELECT device_id, 'freetext', timestamp, schema_version, app_version FROM freetext_records
)
SELECT r.device_id,
       u.nickname,
       u.role                                                      AS user_role,
       pc.participant,
       COUNT(*) FILTER (WHERE r.src = 'tone')                      AS n_tone,
       COUNT(*) FILTER (WHERE r.src = 'aspiration')                AS n_aspiration,
       COUNT(*) FILTER (WHERE r.src = 'freetext')                  AS n_freetext,
       MIN(r.timestamp)                                            AS first_at_utc,
       MAX(r.timestamp)                                            AS last_at_utc,
       string_agg(DISTINCT r.app_version, ', ')                    AS app_versions,
       string_agg(DISTINCT COALESCE(r.schema_version, 1)::text, ', ') AS schema_versions,
       COUNT(*) FILTER (WHERE COALESCE(r.schema_version, 1) >= 6
                          AND r.timestamp < (SELECT release_at FROM cfg)) AS n_prerelease_v6,
       (r.device_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') AS non_standard_id,
       (r.device_id IN (SELECT device_id FROM excluded_devices))  AS in_exclusion_list
FROM raw r
LEFT JOIN users u  ON u.device_id = r.device_id
LEFT JOIN pcode pc ON pc.device_id = r.device_id
GROUP BY r.device_id, u.nickname, u.role, pc.participant
ORDER BY first_at_utc;


-- =====================================================================
-- 1) 参与者概况（论文的样本描述表）
-- 一行一位参与者。tone_attempts = 有成绩的尝试（不含技术失败）；tone_pass_rate 另外去掉质量标记；share_curve_view = 有效尝试中用音高曲线视图的比例
-- （schema_version >= 3 才有自选视图）——只用于描述，不能拿来分组比较。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
tone AS (
    SELECT pc.participant,
           COUNT(*) FILTER (WHERE COALESCE(t.result_status, 'valid_result') <> 'technical_retry') AS tone_attempts,
           COUNT(*) FILTER (WHERE t.result_status = 'technical_retry')                     AS tone_technical_retry,
           ROUND(AVG(CASE WHEN COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false) THEN (t.grade NOT IN ('fail', 'n/a'))::int END)::numeric, 3)                AS tone_pass_rate,
           COUNT(DISTINCT t.lexeme_id) FILTER (WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false))                              AS words_practised,
           COUNT(*) FILTER (WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false) AND t.phase = 'self_test')                       AS self_test_attempts,
           ROUND(AVG(CASE WHEN COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false) AND COALESCE(t.schema_version, 1) >= 3
                           AND t.feedback_mode IS NOT NULL
                          THEN (t.feedback_mode = 'dynamicF0')::int END)::numeric, 3)      AS share_curve_view
    FROM ts t JOIN pcode pc ON pc.device_id = t.device_id
    GROUP BY pc.participant
),
asp_s AS (
    SELECT pc.participant, COUNT(*) AS aspiration_attempts,
           ROUND(AVG(a.passed::int)::numeric, 3) AS aspiration_pass_rate
    FROM asp a JOIN pcode pc ON pc.device_id = a.device_id
    GROUP BY pc.participant
),
ftx_s AS (
    SELECT pc.participant, COUNT(*) AS freetext_records
    FROM ftx f JOIN pcode pc ON pc.device_id = f.device_id
    GROUP BY pc.participant
),
act_s AS (
    SELECT pc.participant,
           MIN(((x.at AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date)            AS first_local_date,
           MAX(((x.at AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date)            AS last_local_date,
           COUNT(DISTINCT ((x.at AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date) AS active_days,
           string_agg(DISTINCT x.app_version, ', ')                            AS app_versions
    FROM (SELECT device_id, timestamp AS at, app_version FROM ts
          UNION ALL SELECT device_id, timestamp, app_version FROM asp
          UNION ALL SELECT device_id, timestamp, app_version FROM ftx) x
    JOIN pcode pc ON pc.device_id = x.device_id
    CROSS JOIN cfg c
    GROUP BY pc.participant
),
dev_s AS (
    SELECT pc.participant,
           COUNT(*)                                          AS n_devices,
           string_agg(DISTINCT u.role, ', ')                 AS roles,
           string_agg(DISTINCT u.native_language, ', ')      AS native_language,
           string_agg(DISTINCT u.spoken_languages::text, ' | ') AS spoken_languages
    FROM pcode pc LEFT JOIN users u ON u.device_id = pc.device_id
    GROUP BY pc.participant
)
SELECT s.participant,
       d.n_devices, d.roles, d.native_language, d.spoken_languages,
       s.first_local_date, s.last_local_date,
       (s.last_local_date - s.first_local_date + 1)  AS span_days,
       s.active_days,
       COALESCE(t.tone_attempts, 0)          AS tone_attempts,
       COALESCE(t.tone_technical_retry, 0)   AS tone_technical_retry,
       t.tone_pass_rate,
       COALESCE(t.words_practised, 0)        AS words_practised,
       COALESCE(t.self_test_attempts, 0)     AS self_test_attempts,
       t.share_curve_view,
       COALESCE(a.aspiration_attempts, 0)    AS aspiration_attempts,
       a.aspiration_pass_rate,
       COALESCE(f.freetext_records, 0)       AS freetext_records,
       s.app_versions
FROM act_s s
JOIN dev_s d USING (participant)
LEFT JOIN tone  t USING (participant)
LEFT JOIN asp_s a USING (participant)
LEFT JOIN ftx_s f USING (participant)
ORDER BY s.participant;


-- =====================================================================
-- 2) 声调长表（每次尝试一行）—— 给 R / SPSS / Excel 做进一步分析
-- 技术失败行保留（看失败分布用），但 dtw_score / passed 留空。
-- attempt_on_word = 该参与者在该词上的第几次有效尝试；day_index = 距该参与者第一条声调记录的天数。
-- prior_practice_count 只在自测行有值：自测前在该词上做过几次有效的普通练习。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
lex(lexeme_id, hanzi, tones, word_set, category) AS (VALUES   -- 词表（来自 App 内置语料 lexemes.json）
    ('xianzai',  '现在', '4-4', 'set1',       'tone'),
    ('dianshi',  '电视', '4-4', 'set2',       'tone'),
    ('sushe',    '宿舍', '4-4', 'assessment', 'tone'),
    ('hanzi',    '汉字', '4-4', 'assessment', 'tone'),
    ('heshui',   '喝水', '1-3', 'assessment', 'tone'),
    ('shenti',   '身体', '1-3', 'set1',       'tone'),
    ('jingli',   '经理', '1-3', 'set2',       'tone'),
    ('yisheng',  '医生', '1-1', 'set1',       'tone'),
    ('qingchu',  '清楚', '1-5', 'set1',       'tone'),
    ('xiuxi',    '休息', '1-5', 'set2',       'tone'),
    ('ziji',     '自己', '4-3', 'set1',       'tone'),
    ('canjia',   '参加', '1-1', 'set2',       'tone'),
    ('zaocan',   '早餐', '3-1', 'set2',       'tone'),
    ('xiangxin', '相信', '1-4', 'assessment', 'tone'),
    ('paobu',    '跑步', '3-4', NULL,         'aspiration'),
    ('bangzhu',  '帮助', '1-4', NULL,         'aspiration'),
    ('tingdong', '听懂', '1-3', NULL,         'aspiration'),
    ('dengdai',  '等待', '3-4', NULL,         'aspiration'),
    ('kaoshi',   '考试', '3-4', NULL,         'aspiration'),
    ('gaosu',    '告诉', '4-5', NULL,         'aspiration')
),
t2 AS (
    SELECT pc.participant, t.id, t.timestamp,
           ((t.timestamp AT TIME ZONE 'UTC') AT TIME ZONE c.tz)            AS local_ts,
           t.lexeme_id, l.hanzi, l.tones,
           COALESCE(t.word_set_id, l.word_set)                             AS word_set,
           ('1' = ANY (string_to_array(l.tones, '-')))                                                     AS contains_tone1,
           (l.tones ~ '^1(-1)*$')                                          AS all_tone1,
           t.phase,
           COALESCE(t.schema_version, 1)                                   AS schema_version,
           NOT (('1' = ANY (string_to_array(l.tones, '-'))) AND COALESCE(t.schema_version, 1) < 4)                                                    AS comparable_across_versions,
           t.app_version, t.feedback_mode, t.reference_type,
           COALESCE(t.result_status, 'valid_result')                       AS result_status,
           t.failure_reason,
           COALESCE(t.quality_flag, false)                                 AS quality_flag,
           (COALESCE(t.result_status, 'valid_result') <> 'technical_retry') AS scored,
           (COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false))                                                       AS valid,
           t.dtw_score, t.grade, t.voiced_frame_count
    FROM ts t
    CROSS JOIN cfg c
    JOIN pcode pc ON pc.device_id = t.device_id
    LEFT JOIN lex l ON l.lexeme_id = t.lexeme_id
)
SELECT participant,
       timestamp                                   AS timestamp_utc,
       local_ts::date                              AS local_date,
       local_ts::date - MIN(local_ts::date) OVER (PARTITION BY participant) AS day_index,
       lexeme_id, hanzi, tones, word_set, contains_tone1, all_tone1,
       phase, schema_version, comparable_across_versions,
       app_version, feedback_mode, reference_type,
       result_status, failure_reason, quality_flag, voiced_frame_count,
       CASE WHEN scored THEN dtw_score END         AS dtw_score,
       CASE WHEN scored THEN grade NOT IN ('fail', 'n/a') END AS passed,
       CASE WHEN scored THEN (schema_version >= 5 AND grade = 'fail' AND dtw_score <= 0.5) END AS gated_level_tone,
       grade,
       CASE WHEN valid THEN ROW_NUMBER() OVER (PARTITION BY participant, lexeme_id, valid
                                                ORDER BY timestamp, id) END AS attempt_on_word,
       CASE WHEN phase = 'self_test'
            THEN COUNT(*) FILTER (WHERE valid AND COALESCE(phase, 'training') = 'training')
                 OVER (PARTITION BY participant, lexeme_id ORDER BY timestamp, id
                       ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) END AS prior_practice_count
FROM t2
ORDER BY participant, timestamp, id;


-- =====================================================================
-- 3) 按声调组合汇总
-- mode：practice = 有反馈的普通练习；no_feedback = 自测（以及历史上的前测 / 后测）。
-- pass_rate 按尝试次数合计（练得多的人权重大）；pass_rate_by_participant 先算每人再平均（每人权重相同）。
-- comparable_across_versions = false 的行是含一声词的旧版分数，不要与其它行合并。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
lex(lexeme_id, hanzi, tones, word_set, category) AS (VALUES   -- 词表（来自 App 内置语料 lexemes.json）
    ('xianzai',  '现在', '4-4', 'set1',       'tone'),
    ('dianshi',  '电视', '4-4', 'set2',       'tone'),
    ('sushe',    '宿舍', '4-4', 'assessment', 'tone'),
    ('hanzi',    '汉字', '4-4', 'assessment', 'tone'),
    ('heshui',   '喝水', '1-3', 'assessment', 'tone'),
    ('shenti',   '身体', '1-3', 'set1',       'tone'),
    ('jingli',   '经理', '1-3', 'set2',       'tone'),
    ('yisheng',  '医生', '1-1', 'set1',       'tone'),
    ('qingchu',  '清楚', '1-5', 'set1',       'tone'),
    ('xiuxi',    '休息', '1-5', 'set2',       'tone'),
    ('ziji',     '自己', '4-3', 'set1',       'tone'),
    ('canjia',   '参加', '1-1', 'set2',       'tone'),
    ('zaocan',   '早餐', '3-1', 'set2',       'tone'),
    ('xiangxin', '相信', '1-4', 'assessment', 'tone'),
    ('paobu',    '跑步', '3-4', NULL,         'aspiration'),
    ('bangzhu',  '帮助', '1-4', NULL,         'aspiration'),
    ('tingdong', '听懂', '1-3', NULL,         'aspiration'),
    ('dengdai',  '等待', '3-4', NULL,         'aspiration'),
    ('kaoshi',   '考试', '3-4', NULL,         'aspiration'),
    ('gaosu',    '告诉', '4-5', NULL,         'aspiration')
),
v AS (
    SELECT pc.participant, l.tones,
           CASE WHEN t.phase IN ('self_test', 'pretest', 'posttest') THEN 'no_feedback' ELSE 'practice' END                     AS mode,
           NOT (('1' = ANY (string_to_array(l.tones, '-'))) AND COALESCE(t.schema_version, 1) < 4)               AS comparable_across_versions,
           t.dtw_score,
           (t.grade NOT IN ('fail', 'n/a'))                   AS passed,
           (COALESCE(t.schema_version, 1) >= 5 AND t.grade = 'fail' AND t.dtw_score <= 0.5) AS gated
    FROM ts t
    JOIN pcode pc ON pc.device_id = t.device_id
    JOIN lex l    ON l.lexeme_id = t.lexeme_id
    WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false)
),
per_p AS (
    SELECT tones, mode, comparable_across_versions, participant, AVG(passed::int) AS p_rate
    FROM v GROUP BY 1, 2, 3, 4
),
by_p AS (
    SELECT tones, mode, comparable_across_versions, ROUND(AVG(p_rate)::numeric, 3) AS pass_rate_by_participant
    FROM per_p GROUP BY 1, 2, 3
)
SELECT v.tones, v.mode, v.comparable_across_versions,
       COUNT(DISTINCT v.participant)                                                AS n_participants,
       COUNT(*)                                                                     AS n_attempts,
       ROUND(AVG(v.passed::int)::numeric, 3)                                        AS pass_rate,
       b.pass_rate_by_participant,
       ROUND(AVG(v.dtw_score)::numeric, 3)                                          AS mean_dtw,
       ROUND(percentile_cont(0.25) WITHIN GROUP (ORDER BY v.dtw_score)::numeric, 3) AS q1_dtw,
       ROUND(percentile_cont(0.5)  WITHIN GROUP (ORDER BY v.dtw_score)::numeric, 3) AS median_dtw,
       ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY v.dtw_score)::numeric, 3) AS q3_dtw,
       COUNT(*) FILTER (WHERE v.gated)                                              AS n_gated_level_tone
FROM v
JOIN by_p b USING (tones, mode, comparable_across_versions)
GROUP BY v.tones, v.mode, v.comparable_across_versions, b.pass_rate_by_participant
ORDER BY v.mode, v.comparable_across_versions DESC, v.tones;


-- =====================================================================
-- 4) 按词汇总（只算有反馈的普通练习）
-- first_try_pass_rate = 每人在该词上第 1 次有效尝试的通过率；try_2_5 / try_6_plus 同理。
-- 次数按该词的全部有效练习算：第 1 次落在旧版本的人，在可比较那一行里就没有 first_try。
-- 后面几次只有坚持练下去的人才有，通过率变化不能直接当作「学会了」（幸存者偏差）。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
lex(lexeme_id, hanzi, tones, word_set, category) AS (VALUES   -- 词表（来自 App 内置语料 lexemes.json）
    ('xianzai',  '现在', '4-4', 'set1',       'tone'),
    ('dianshi',  '电视', '4-4', 'set2',       'tone'),
    ('sushe',    '宿舍', '4-4', 'assessment', 'tone'),
    ('hanzi',    '汉字', '4-4', 'assessment', 'tone'),
    ('heshui',   '喝水', '1-3', 'assessment', 'tone'),
    ('shenti',   '身体', '1-3', 'set1',       'tone'),
    ('jingli',   '经理', '1-3', 'set2',       'tone'),
    ('yisheng',  '医生', '1-1', 'set1',       'tone'),
    ('qingchu',  '清楚', '1-5', 'set1',       'tone'),
    ('xiuxi',    '休息', '1-5', 'set2',       'tone'),
    ('ziji',     '自己', '4-3', 'set1',       'tone'),
    ('canjia',   '参加', '1-1', 'set2',       'tone'),
    ('zaocan',   '早餐', '3-1', 'set2',       'tone'),
    ('xiangxin', '相信', '1-4', 'assessment', 'tone'),
    ('paobu',    '跑步', '3-4', NULL,         'aspiration'),
    ('bangzhu',  '帮助', '1-4', NULL,         'aspiration'),
    ('tingdong', '听懂', '1-3', NULL,         'aspiration'),
    ('dengdai',  '等待', '3-4', NULL,         'aspiration'),
    ('kaoshi',   '考试', '3-4', NULL,         'aspiration'),
    ('gaosu',    '告诉', '4-5', NULL,         'aspiration')
),
v AS (
    SELECT pc.participant, t.lexeme_id, l.hanzi, l.tones, l.word_set,
           NOT (('1' = ANY (string_to_array(l.tones, '-'))) AND COALESCE(t.schema_version, 1) < 4)  AS comparable_across_versions,
           t.dtw_score,
           (t.grade NOT IN ('fail', 'n/a'))      AS passed,
           (COALESCE(t.schema_version, 1) >= 5 AND t.grade = 'fail' AND t.dtw_score <= 0.5) AS gated,
           ROW_NUMBER() OVER (PARTITION BY pc.participant, t.lexeme_id ORDER BY t.timestamp, t.id) AS k
    FROM ts t
    JOIN pcode pc ON pc.device_id = t.device_id
    JOIN lex l    ON l.lexeme_id = t.lexeme_id
    WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false)
      AND COALESCE(t.phase, 'training') NOT IN ('self_test', 'pretest', 'posttest')
),
per_p AS (
    SELECT lexeme_id, comparable_across_versions, participant, AVG(passed::int) AS p_rate
    FROM v GROUP BY 1, 2, 3
),
by_p AS (
    SELECT lexeme_id, comparable_across_versions, ROUND(AVG(p_rate)::numeric, 3) AS pass_rate_by_participant
    FROM per_p GROUP BY 1, 2
)
SELECT v.lexeme_id, v.hanzi, v.tones, v.word_set, v.comparable_across_versions,
       COUNT(DISTINCT v.participant)                                                AS n_participants,
       COUNT(*)                                                                     AS n_attempts,
       ROUND(AVG(v.passed::int)::numeric, 3)                                        AS pass_rate,
       b.pass_rate_by_participant,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY v.dtw_score)::numeric, 3) AS median_dtw,
       ROUND(AVG(v.passed::int) FILTER (WHERE v.k = 1)::numeric, 3)                 AS first_try_pass_rate,
       ROUND(AVG(v.passed::int) FILTER (WHERE v.k BETWEEN 2 AND 5)::numeric, 3)     AS try_2_5_pass_rate,
       ROUND(AVG(v.passed::int) FILTER (WHERE v.k >= 6)::numeric, 3)                AS try_6_plus_pass_rate,
       COUNT(*) FILTER (WHERE v.gated)                                              AS n_gated_level_tone
FROM v
JOIN by_p b USING (lexeme_id, comparable_across_versions)
GROUP BY v.lexeme_id, v.hanzi, v.tones, v.word_set, v.comparable_across_versions, b.pass_rate_by_participant
ORDER BY v.tones, v.lexeme_id, v.comparable_across_versions DESC;


-- =====================================================================
-- 5) 重复练习曲线（第 k 次尝试的通过率，只算有反馈的普通练习）
-- attempt_k = 该参与者在同一个词上的第 k 次有效尝试，10 表示第 10 次及以后。
-- 只用可跨版本比较的记录。n_participants 随 k 下降：后面的点只代表坚持练的人，描述用，不作因果解释。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
lex(lexeme_id, hanzi, tones, word_set, category) AS (VALUES   -- 词表（来自 App 内置语料 lexemes.json）
    ('xianzai',  '现在', '4-4', 'set1',       'tone'),
    ('dianshi',  '电视', '4-4', 'set2',       'tone'),
    ('sushe',    '宿舍', '4-4', 'assessment', 'tone'),
    ('hanzi',    '汉字', '4-4', 'assessment', 'tone'),
    ('heshui',   '喝水', '1-3', 'assessment', 'tone'),
    ('shenti',   '身体', '1-3', 'set1',       'tone'),
    ('jingli',   '经理', '1-3', 'set2',       'tone'),
    ('yisheng',  '医生', '1-1', 'set1',       'tone'),
    ('qingchu',  '清楚', '1-5', 'set1',       'tone'),
    ('xiuxi',    '休息', '1-5', 'set2',       'tone'),
    ('ziji',     '自己', '4-3', 'set1',       'tone'),
    ('canjia',   '参加', '1-1', 'set2',       'tone'),
    ('zaocan',   '早餐', '3-1', 'set2',       'tone'),
    ('xiangxin', '相信', '1-4', 'assessment', 'tone'),
    ('paobu',    '跑步', '3-4', NULL,         'aspiration'),
    ('bangzhu',  '帮助', '1-4', NULL,         'aspiration'),
    ('tingdong', '听懂', '1-3', NULL,         'aspiration'),
    ('dengdai',  '等待', '3-4', NULL,         'aspiration'),
    ('kaoshi',   '考试', '3-4', NULL,         'aspiration'),
    ('gaosu',    '告诉', '4-5', NULL,         'aspiration')
),
v AS (     -- k 按全部有效练习计数（与第 4 段一致），再只取可比较的记录
    SELECT pc.participant,
           (t.grade NOT IN ('fail', 'n/a')) AS passed, t.dtw_score,
           NOT (('1' = ANY (string_to_array(l.tones, '-'))) AND COALESCE(t.schema_version, 1) < 4) AS comparable,
           ROW_NUMBER() OVER (PARTITION BY pc.participant, t.lexeme_id ORDER BY t.timestamp, t.id) AS k
    FROM ts t
    JOIN pcode pc ON pc.device_id = t.device_id
    JOIN lex l    ON l.lexeme_id = t.lexeme_id
    WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false)
      AND COALESCE(t.phase, 'training') NOT IN ('self_test', 'pretest', 'posttest')
)
SELECT LEAST(k, 10)                                                              AS attempt_k,
       COUNT(DISTINCT participant)                                               AS n_participants,
       COUNT(*)                                                                  AS n_attempts,
       ROUND(AVG(passed::int)::numeric, 3)                                       AS pass_rate,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dtw_score)::numeric, 3) AS median_dtw
FROM v
WHERE comparable
GROUP BY LEAST(k, 10)
ORDER BY attempt_k;


-- =====================================================================
-- 6) 每日使用情况（摩洛哥时间）
-- new_participants = 当天第一次出现的参与者数。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
x AS (
    SELECT pc.participant,
           ((t.timestamp AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date AS local_date,
           'tone' AS src,
           (COALESCE(t.result_status, 'valid_result') <> 'technical_retry') AS scored
    FROM ts t JOIN pcode pc ON pc.device_id = t.device_id CROSS JOIN cfg c
    UNION ALL
    SELECT pc.participant, ((a.timestamp AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date, 'aspiration', true
    FROM asp a JOIN pcode pc ON pc.device_id = a.device_id CROSS JOIN cfg c
    UNION ALL
    SELECT pc.participant, ((f.timestamp AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date, 'freetext', true
    FROM ftx f JOIN pcode pc ON pc.device_id = f.device_id CROSS JOIN cfg c
),
first_day AS (SELECT participant, MIN(local_date) AS d0 FROM x GROUP BY participant)
SELECT x.local_date,
       COUNT(DISTINCT x.participant)                                        AS active_participants,
       COUNT(DISTINCT x.participant) FILTER (WHERE x.local_date = f.d0)     AS new_participants,
       COUNT(*) FILTER (WHERE x.src = 'tone' AND x.scored)                  AS tone_attempts,
       COUNT(*) FILTER (WHERE x.src = 'tone' AND NOT x.scored)              AS tone_technical_retry,
       COUNT(*) FILTER (WHERE x.src = 'aspiration')                         AS aspiration_attempts,
       COUNT(*) FILTER (WHERE x.src = 'freetext')                           AS freetext_records
FROM x JOIN first_day f USING (participant)
GROUP BY x.local_date
ORDER BY x.local_date;


-- =====================================================================
-- 7) 技术失败与数据质量（按 App 版本）
-- 分母是该版本全部声调记录（含失败）。旧版本没有 result_status 列时记为有效。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
)
SELECT COALESCE(t.app_version, '(未记录)')                                     AS app_version,
       COUNT(DISTINCT t.device_id)                                              AS n_devices,
       COUNT(*)                                                                 AS tone_records,
       COUNT(*) FILTER (WHERE t.result_status = 'technical_retry')              AS technical_retry,
       ROUND(100.0 * COUNT(*) FILTER (WHERE t.result_status = 'technical_retry')
             / NULLIF(COUNT(*), 0), 1)                                          AS pct_technical_retry,
       COUNT(*) FILTER (WHERE t.failure_reason = 'insufficient_voiced_frames')  AS fail_no_voice,
       COUNT(*) FILTER (WHERE t.failure_reason = 'permission_denied')           AS fail_permission,
       COUNT(*) FILTER (WHERE t.failure_reason = 'recording_interrupted')       AS fail_interrupted,
       COUNT(*) FILTER (WHERE t.failure_reason = 'low_signal_quality')          AS fail_low_signal,
       COUNT(*) FILTER (WHERE t.failure_reason = 'analysis_error')              AS fail_analysis,
       COUNT(*) FILTER (WHERE COALESCE(t.quality_flag, false)
                           OR t.result_status = 'quality_flagged')              AS quality_flagged,
       COUNT(*) FILTER (WHERE COALESCE(t.reference_switched, false))            AS reference_switched  -- 应为 0
FROM ts t
GROUP BY COALESCE(t.app_version, '(未记录)')
ORDER BY app_version;


-- =====================================================================
-- 8) 送气练习（每人每词一行）
-- 通过线：触发率 >= 0.6。送气练习不进新版研究表，只在这里。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
a2 AS (
    SELECT pc.participant, a.target_word, a.trigger_rate, a.passed, a.timestamp,
           ROW_NUMBER() OVER (PARTITION BY pc.participant, a.target_word ORDER BY a.timestamp, a.id) AS k,
           COUNT(*)     OVER (PARTITION BY pc.participant, a.target_word)                         AS n
    FROM asp a JOIN pcode pc ON pc.device_id = a.device_id
)
SELECT participant, target_word,
       MAX(n)                                                                       AS n_attempts,
       ROUND(AVG(passed::int)::numeric, 3)                                          AS pass_rate,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY trigger_rate)::numeric, 3) AS median_trigger_rate,
       ROUND(MAX(trigger_rate) FILTER (WHERE k = 1)::numeric, 3)                    AS first_trigger_rate,
       ROUND(MAX(trigger_rate) FILTER (WHERE k = n)::numeric, 3)                    AS last_trigger_rate
FROM a2
GROUP BY participant, target_word
ORDER BY participant, target_word;


-- =====================================================================
-- 9a) 自由文本（每人一行）
-- 不导出学习者输入的原文（可能含个人信息），只给数量。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
f2 AS (
    SELECT pc.participant, f.*, ((f.timestamp AT TIME ZONE 'UTC') AT TIME ZONE c.tz)::date AS local_date
    FROM ftx f JOIN pcode pc ON pc.device_id = f.device_id CROSS JOIN cfg c
)
SELECT participant,
       COUNT(*)                                  AS records,
       COUNT(DISTINCT original_text)             AS distinct_texts,
       COUNT(DISTINCT tokenized_word)            AS distinct_words,
       ROUND(AVG(duration)::numeric, 2)          AS mean_duration_s,
       MIN(local_date)                           AS first_local_date,
       MAX(local_date)                           AS last_local_date
FROM f2
GROUP BY participant
ORDER BY participant;


-- =====================================================================
-- 9b) 自由文本里练过的词（按词）
-- 只列至少 2 位参与者练过的词：只有一个人输入过的词可能认得出是谁（例如人名）。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
)
SELECT f.tokenized_word, f.pinyin,
       COUNT(*)                       AS records,
       COUNT(DISTINCT pc.participant) AS n_participants
FROM ftx f JOIN pcode pc ON pc.device_id = f.device_id
GROUP BY f.tokenized_word, f.pinyin
HAVING COUNT(DISTINCT pc.participant) >= 2
ORDER BY n_participants DESC, records DESC;


-- =====================================================================
-- 10) 自测（每人一行，schema_version >= 6 才有）
-- 自测是学习者自己选的，界面上不显示成绩，后台照常评分。只做描述，不是前后测。
-- =====================================================================
WITH
cfg AS (
    SELECT TIMESTAMP '2026-10-14 00:00' AS release_at,          -- 【参数 1】2.0 上架时间（UTC）
           'Africa/Casablanca'::text    AS tz
),
excluded_devices(device_id) AS (
    VALUES ('device-test'), ('sim'), ('dev')                     -- 【参数 2】要排除的设备号
),
ts AS (    -- 声调记录（已排除测试与教师）
    SELECT t.* FROM training_sessions t CROSS JOIN cfg
    WHERE t.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND t.role <> 'teacher'
      AND NOT (COALESCE(t.schema_version, 1) >= 6 AND t.timestamp < cfg.release_at)
),
asp AS (   -- 送气记录
    SELECT a.* FROM aspiration_attempts a CROSS JOIN cfg
    WHERE a.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND a.role <> 'teacher'
      AND NOT (COALESCE(a.schema_version, 1) >= 6 AND a.timestamp < cfg.release_at)
),
ftx AS (   -- 自由文本记录
    SELECT f.* FROM freetext_records f CROSS JOIN cfg
    WHERE f.device_id NOT IN (SELECT device_id FROM excluded_devices)
      AND f.role <> 'teacher'
      AND NOT (COALESCE(f.schema_version, 1) >= 6 AND f.timestamp < cfg.release_at)
),
who AS (   -- 设备 → 人
    SELECT d.device_id, COALESCE(u.account_id, d.device_id) AS person
    FROM (SELECT device_id FROM ts UNION SELECT device_id FROM asp UNION SELECT device_id FROM ftx) d
    LEFT JOIN users u ON u.device_id = d.device_id
),
pcode AS ( -- 人 → 匿名编号
    SELECT w.device_id,
           'P' || LPAD(DENSE_RANK() OVER (ORDER BY f.first_at, w.person)::text, 3, '0') AS participant
    FROM who w
    JOIN (SELECT w2.person, MIN(x.at) AS first_at
          FROM (SELECT device_id, timestamp AS at FROM ts
                UNION ALL SELECT device_id, timestamp FROM asp
                UNION ALL SELECT device_id, timestamp FROM ftx) x
          JOIN who w2 ON w2.device_id = x.device_id
          GROUP BY w2.person) f ON f.person = w.person
),
t2 AS (
    SELECT pc.participant, t.lexeme_id, t.phase, t.grade, t.dtw_score,
           (COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false)) AS valid,
           COUNT(*) FILTER (WHERE COALESCE(t.result_status, 'valid_result') = 'valid_result' AND NOT COALESCE(t.quality_flag, false) AND COALESCE(t.phase, 'training') = 'training')
               OVER (PARTITION BY pc.participant, t.lexeme_id ORDER BY t.timestamp, t.id
                     ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prior_practice_count
    FROM ts t JOIN pcode pc ON pc.device_id = t.device_id
)
SELECT participant,
       COUNT(*)                                                                         AS self_test_attempts,
       COUNT(DISTINCT lexeme_id)                                                        AS words,
       ROUND(AVG((grade NOT IN ('fail', 'n/a'))::int)::numeric, 3)                       AS pass_rate,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY dtw_score)::numeric, 3)        AS median_dtw,
       ROUND(percentile_cont(0.5) WITHIN GROUP (ORDER BY prior_practice_count)::numeric, 1) AS median_prior_practice,
       COUNT(*) FILTER (WHERE prior_practice_count = 0)                                 AS never_practised_before
FROM t2
WHERE phase = 'self_test' AND valid
GROUP BY participant
ORDER BY participant;
