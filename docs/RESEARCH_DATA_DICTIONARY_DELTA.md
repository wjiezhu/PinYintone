# 研究数据字典：相对 v1 的增补与偏离

研究字段字典的主文件是研究者手里的《新版研究_数据表与字段字典_v1》。
本文件只记录**代码实际实现与 v1 不同或 v1 没写到的地方**，供更新主文件时逐条对照。
主文件更新后，本文件对应条目可以删除。

版本：2026-10-13（对应需求 2.3 版、本机记录 `schemaVersion = 6`、导出格式 `research-export-2.0`）。

> 状态与枚举的唯一真源是 `backend/app/routers/research.py` 顶部的常量与
> `backend/app/research_models.py` 的列定义。本文件与它们不一致时，以代码为准并请修正本文件。

## 1. 新增的列

| 表 | 列 | 类型 | 含义 |
|---|---|---|---|
| `users` | `account_id` | 字符串，可空 | 同一个 Apple 账号在不同设备上的行共用的随机内部编号。纳入时按它查找已有参与者，所以换设备不会多出一位。**不进研究导出。** |
| `research_manifests` | `is_test` | 布尔，默认假 | 测试配置。只下发给开发构建；其下参与者一律 `is_test = true`。 |
| `research_manifests` | `compatible_builds` | JSON 数组，可空 | 除 `build_number` 外还允许采集的构建号（修复版本）。 |
| `research_manifests` | `survey_forms` | JSON，可空 | 每份问卷绑定的 `form_version` 与 `translation_version`。上传的问卷版本与此不符即拒收。 |
| `research_participants` | `enrolled_manifest_id` | 字符串，可空 | 纳入时所依据的配置。 |
| `research_survey_instances` | `received_at` | 时间 | 服务端**首次**收到这份问卷的时间。 |
| `research_survey_instances` | `updated_at` | 时间 | 服务端最近一次接受状态更新的时间。 |

新增一张业务表 **`account_links`**（`apple_user_id` 主键、`account_id` 唯一、`created_at`）：
Apple 账号到内部编号的对应关系。设备行会被换账号登录改写，对应关系必须单独存一份。
它是业务表，**不进研究导出**；`research_identity_map.internal_user_id` 存的是 `account_id`，
不是设备号，更不是 Apple 标识。删除账号时这一行一并删除。

全部是增量迁移（`ADD COLUMN` 与新建表），旧行不改写。

## 2. 取值范围的变化

### `research_attempts.task_type`
`fixed_word` / `free_text` / **`self_test`**（v1 没有 `self_test`）。

- `self_test`：学习者主动开始的可选自测。照常算分入库，但**不向学习者呈现任何评价**，
  `result_displayed_at` 恒为空，因此不计入使用后问卷的触发次数。
- 自选自测存在自选择偏差，**不得当作前后测证据**。

### `research_attempts.status`
`recording` / `cancelled` / `recording_failed` / `analyzing` / `analysis_failed` /
`succeeded` / **`interrupted_unknown`**。

- `cancelled`：用户主动取消或离开页面。不是错误，不要求错误码。
- `interrupted_unknown`：App 被杀或崩溃，来不及收尾。下次启动时由端侧补记。
- **没有成绩的状态（除 `succeeded` 之外的全部）`metric_value` 与 `passed` 必须为 NULL**，
  服务端拒收带分的失败记录。`metric_value` 必须是有限数，NaN / Infinity 拒收。
- 旧业务表里的 `-1` / `"n/a"` 哨兵只在旧表里存在，**研究表不使用哨兵**。

### `research_survey_instances.status`
`invited` / `in_progress` / `deferred` / `declined` / `partial` / `complete`。

| 状态 | 含义 | 是否最终 |
|---|---|---|
| `invited` | 已邀请，还没动 | 否 |
| `in_progress` | 有草稿 | 否 |
| `deferred` | 用户点了「稍后填写」 | 否 |
| `declined` | 用户明确不填写，或提交时一题都没答 | 是 |
| `partial` | 用户主动提交，但有题跳过或未答 | 是 |
| `complete` | 用户主动提交，全部有答 | 是 |

服务端按等级只进不退（`invited` 0 < `in_progress` / `deferred` 1 < 三种最终状态 2）：
最终状态之后的重传幂等，不会被旧草稿覆盖。**「稍后填写」「明确不填写」「跳过某题」是三件不同的事。**

### `research_survey_instances.timing_class`
`background` / `before_first_attempt` / `after_practice` / `late_pre`。

`late_pre` = 前置问卷在首次练习**开始之后**才完成。判定只看完成时间与首次练习开始时间的先后，
**与上传时间、服务端接收时间无关**——练习前已完成、只是离线晚传的仍是 `before_first_attempt`。

### `research_participants.eligibility_status`
`eligible` / `excluded` / `pending`。纳入接口只接受端侧已判 `eligible` 者；
背景表到达后服务端按答案复核，复核不符则改为 `excluded` 并拒收其后续研究数据。

### `research_advice_requests.evidence_snapshot` 的键 ⚠ 偏离
允许的键：`signal_status` / `metric_name` / `metric_value` / **`gate`**。

`gate` 记录平调词走向闸门是否触发，v1 没有这个键。它是明确计算、有阈值依据的**整词**特征，
不是未经核验的音节级诊断（见 `docs/V2_DECISIONS.md` 第 11、24 条）。

`source_type` 本轮只接受 `teacher_hint_only` / `rule_feedback`；`ai_generated` 拒收（本轮不接 AI）。
`evidence_codes` 只接受 `signal_unusable` / `overall_metric` / `none`。

## 3. 接口约定

| 约定 | 内容 |
|---|---|
| 问卷幂等键 | `surveyInstanceID`：客户端在**邀请时**生成，同一份问卷的所有状态更新与重传都用它 |
| 邀请时间 | `invitedAt`：首次写入后不被后续上传覆盖 |
| 批量确认 | 尝试、事件、建议的批量接口返回 `received` / `inserted` / `duplicates` / `rejected`。`rejected` 逐条给出编号与原因——**接口 200 不等于每一条都已入库** |
| 配置下发 | `/research/manifest/active` 必须带 `appVersion` 与 `build`；不带或不匹配则没有配置可用 |
| 时间 | 一律 ISO8601 带时区；数字时间戳拒收（422） |

### 拒收原因码（冒号前是机器可读的部分）

| HTTP | 原因码 | 何时 |
|---|---|---|
| 403 | `no_active_consent` | 没有有效同意（未同意，或已退出） |
| 403 | `not_eligible` | 参与者已被判不符合 |
| 409 | `account_required` | 还没有学生账号就调用纳入 |
| 409 | `eligibility_required` | 端侧没有判为符合 |
| 409 | `consent_version_mismatch` | 同意文本版本与配置不符 |
| 409 | `form_version_mismatch` | 问卷或译文版本与配置绑定的不符 |
| 409 | `window_closed` | 窗口外不再纳入新参与者 |
| 409 | `outside_window` | 问卷的邀请或完成不在窗口内 |
| 409 | `withdrawn` | 已退出者本轮不再重新纳入 |
| 409 | `id_conflict` | 实例编号已被另一份问卷占用 |

## 4. 导出（`export_research.py`，格式 `research-export-2.0`）

文件：`participants.csv`、`attempts.csv`、`interaction_events.csv`、`survey_instances.csv`、
`survey_answers.csv`、`advice_requests.csv`、`issue_reports.csv`、`lexemes.csv`、
`manifests.csv`、`export_meta.json`、`summary.json`。

- 默认排除：`is_test = true`、不符合条件者、撤回者、窗口外发生的记录、不属于指定配置的记录。
  `--include-test` 用于核对测试资料，导出里带醒目的测试标记。
- `--cutoff`：数据截止时点。截止之后才**收到**的资料不进本次导出，数量记在
  `export_meta.json` 的 `arrived_after_cutoff`。
- `export_meta.json`：后端提交号、导出格式版本、配置清单、截止时点、纳入排除规则、各表行数、
  解释边界（`interpretation_limits`）。
- `summary.json`：研究者核对用的最小汇总——纳入人数、背景提交人数、前置与使用后问卷各状态人数、
  成功与各类失败尝试数、去重后事件数、版本与测试标记分布。
- 参与者数按研究编号去重；通过与否以 `passed` 为准，**不要用 `metric_value <= 0.5` 重算**
  （平调词走向闸门会让两者不一致）。
- 身份映射表 `research_identity_map` 与 `users` **不导出**。

## 5. 本机（iOS）记录

- `RecordSchema.version = 6`。旧业务表的 `phase`：普通练习写 `training`，自测写 `self_test`；
  `pretest` / `posttest` 不再产生。
- 研究状态按账号分开保存（身份、计数、问卷草稿、待传队列），切换账号互不可见。
- 待传队列持久化在本机；被服务端明确拒收的条目移出队列并计数，不无限重试。
