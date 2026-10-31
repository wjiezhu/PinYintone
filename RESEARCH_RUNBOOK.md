# Pinyintone 研究操作手册

从发版到取数据的完整流程。详细部署见 `DEPLOY.md`，被试说明见 `PARTICIPANT_GUIDE.md`，
设计决定见 `docs/V2_DECISIONS.md`，字段见 `docs/RESEARCH_DATA_DICTIONARY_DELTA.md`。

> **2026-10-13 起（需求 2.3 版）**：没有强制的前测 / 训练 / 后测，没有新旧用户之分，
> 没有固定 14 天窗口。新版研究数据走独立的 `research_*` 表，用 `export_research.py` 导出；
> 下面第 5 节的 `export.sql` 只适用于**旧业务表的历史数据**，不能代替新版研究导出。

## A. 新版研究采集（现行）

### A1. 几件事要分开说
「开发完成」「通过真机验收」「后端已部署」「已提交审核」「App Store 可下载」「已开启正式采集」
是六件不同的事，报告时分别说明，不合并成「已上线」。

### A2. 学习者看到的流程
选语言 → 用 Apple 账号登录 → **直接可以练习** → 首页或「设置 → 研究参与」里自愿参加 →
知情说明 → 背景表（5 题）→ 符合条件则纳入 → 练习前问卷邀请（6 题，可稍后、可不填）→
照常练习 → 第 5 次固定词结果看完后邀请使用后问卷（5 题，可稍后、可不填）。

- 不参加、不符合条件、中途离开，都不影响任何功能。
- 麦克风权限在第一次点录音时才申请。
- 纳入条件：同意 + 成年 + 国籍包含摩洛哥 + 正在学 HSK1–3。**不区分新旧用户。**
  关键题没答不推定符合。
- 「退出研究」和「删除账号」是两个入口。退出后账号和学习记录都在；**本轮退出后不能再次参加**。

### A3. 研究配置清单（唯一真源，改了请同步这里）

| 项 | 测试配置（已有） | 正式配置 |
|---|---|---|
| 研究编号 `study_id` | `pinyintone-uitest` 等，随测试而定 | 由研究者确定 |
| App 版本 / 构建号 | 2.0 / 20 | 取**实际上架并可下载**的那个构建（17 登录会卡住、18 带草稿材料、19 装不上 iOS 16，均不上架） |
| 词库版本 | `lex-2026.10`（20 词，研究者 2026-10-14 核对确认，出处：研究者根据 HSK1–3 课程内容自选） | 同左（已全部 `approved`） |
| 评分规则版本 | `scoring-v5`（DTW ≤ 0.5 + 平调词走向闸门，归一化带下限） | 同左，不因改版调整 |
| 反馈版本 | `fb-1.0` | 同左 |
| 纳入规则版本 | `eligibility-2.0`（不含新旧用户条件） | 同左 |
| 知情同意文本 | `consent-1.0`（研究者 2026-10-14 审定；退出前资料匿名保留、可用于论文） | 同左 |
| 问卷与译文 | `*-1.0` / `research-survey-i18n-1.0`（研究者 2026-10-14 定稿；译文由开发方翻译、研究者确认使用） | 同左 |
| 使用后问卷触发次数 | 5 | 5（研究者已确认） |
| 积分 | 关闭 | 关闭 |
| 采集窗口 | 测试时临时指定 | **由研究者与导师确定**，开发不代选 |

正式配置的三个前提——审定的同意文本、核对过的词条、确定的窗口——都由研究者提供。
截至 2026-10-14，前两项已齐，**只差采集窗口与研究编号**。
材料还是草稿时，`seed_manifest.py` **拒绝**冻结成正式配置，只能加 `--test`。

### A4. 冻结一份配置
```bash
cd backend
python scripts/seed_manifest.py \
  --study-id <研究编号> --app-version 2.0 --build-number 20 \
  --lexicon-version lex-2026.10 --scoring-version scoring-v5 \
  --feedback-version fb-1.0 --advice-policy-version <版本> \
  --survey-version <版本> --consent-version <版本> --eligibility-version eligibility-2.0 \
  --collection-start 2026-10-20T00:00:00+01:00 \
  --collection-end   2026-10-26T00:00:00+01:00 \
  --test
```
- 开始与结束必须带时区，左闭右开。上面的日期只是**格式示例**。
- 去掉 `--test` 即为正式配置；材料不齐时脚本会列出缺什么并拒绝。
- 修复版本上架后，用 `--compatible-builds 18 19` 把新构建号加进允许范围（需新冻结一份配置，
  已冻结的配置不原地改写）。
- 配置只下发给**说明了自己版本且匹配**的 App。旧构建拿不到配置，研究入口对它不出现。

### A5. 采集期间怎么看数据有没有进来
```bash
python scripts/export_research.py --manifest-ids <配置编号> --out-dir out/
cat out/summary.json
```
`summary.json` 给出：纳入人数、背景提交人数、前置与使用后问卷各状态人数、成功与各类失败尝试数、
去重后事件数、版本与测试标记分布。人数按研究编号去重。

### A6. 定稿导出
```bash
python scripts/export_research.py --manifest-ids <配置编号> --out-dir final/ \
  --cutoff 2026-10-27T12:00:00+01:00
```
- 默认排除：测试账号、不符合条件者、撤回者、窗口外发生的记录。
- `--cutoff` 之后才**收到**的资料不进这次导出，数量记在 `export_meta.json` 里。
  窗口内发生、截止前补传到的离线记录照常纳入。
- 核对测试资料时加 `--include-test`，**不要**把这种导出当正式结果。
- `export_meta.json` 记着后端提交号、配置清单、截止时点、纳入排除规则和各表行数，
  论文里的数字要能对回这份文件。

### A7. 取数时最容易错的几处
- **通过与否看 `passed`**，不要用 `metric_value <= 0.5` 重算：全一声的词掉调超过 3 个半音
  会被走向闸门判不通过，分数本身看不出来。
- **没有成绩的尝试是 NULL**，不是 0 也不是 -1。`cancelled`（主动取消）、
  `recording_failed` / `analysis_failed`（技术失败）、`interrupted_unknown`（被杀或崩溃）
  各是各的，不要合成一类「失败」。
- **`self_test` 是自选的**，有自选择偏差，不能当前后测证据。
- **`feedback_mode` 是自选的**，不能做组间比较。
- **`late_pre`** 的前置问卷是开始练习之后才完成的，不算练习前调查。
- 问卷的 `declined`（明确不填）、`deferred`（稍后）、`partial`（提交了但有题没答）要分开统计；
  **没传到服务器的问卷不会出现在导出里**，这与「没作答」是两回事。
- 送气练习不进研究表。
- 分数、通过与否是**形成性反馈与应用日志指标**，不是语言能力测量。

### A8. 上线前的接口自检
```bash
python scripts/verify_pipeline.py --base-url <后端地址> \
  --app-version 2.0 --build 20 --lexeme-version <某个词条版本编号> --export-dir /tmp/verify
```
它会用一个测试账号把纳入、上传、重复上传、退出拒收、导出都走一遍。
**只对着有测试配置的环境跑**，不要对着正在正式采集的库跑。
接口自检通过不代表 App 里的流程通过——那要用真机实际操作一遍。

---

### A9. 现场实测轮（App 2.1 / 构建 21 起，2026-10-28 研究者决定）

**改了什么**
- 已参加研究的人，在研究者在场时从首页「开始现场实测」进入：
  第一步读 6 个测试词（不显示结果）→ 第二步练 8 个训练词（有反馈，每词 3 次有效结果）→
  第三步把 6 个测试词再读一遍（不显示结果）。约 15–20 分钟，随时可退出，不拦普通练习。
- 纳入不限国籍（eligibility-3.0），国籍照常记录。成年与 HSK 1–3 不变。
- 录音上传：代码已就绪，**等导师确认**。确认前用 consent-1.1（不含录音）冻结配置，录音一条都不留；
  确认后用 consent-2.0 + `--audio-upload` 再冻结一份配置，**不需要重新提审 App**（文本不改的前提下）。
- 新一轮用**新的 study_id**，与第一轮（pinyintone-2026-ma）分开。

**上线前必须由研究者 / 导师定的**（开发方只起草，不代填）
1. 实测协议 `PinYintone/Resources/Corpus/field_protocol.json`：测试词、训练词、每词次数。
   现在是草稿：按声调组合拆成测试 6（汉字 喝水 参加 休息 相信 早餐）、训练 8（现在 电视 宿舍
   身体 经理 医生 清楚 自己）。改词就改这个文件，并重新出构建。
2. 同意文本 consent-1.1 / consent-2.0（四种语言，在 Localizable.strings 的 `consent_*` 键）。
3. 审定后在 `backend/research_materials_approval.json` 填日期——**只能研究者本人确认后填**。

**冻结配置**（App 上架之后，连线上库，须研究者当场同意）
```
python3 scripts/seed_manifest.py \
  --study-id <新的 study_id> --app-version 2.1 --build-number 21 \
  --lexicon-version lex-2026.10 --scoring-version scoring-v5 \
  --feedback-version fb-1.0 --advice-policy-version advice-1.0 \
  --survey-version survey-1.2 --consent-version consent-1.1 \
  --eligibility-version eligibility-3.0 \
  --collection-start <上架时刻，带时区> \
  --field-protocol
```
导师确认录音后：同样的命令，把 `--consent-version` 换成 `consent-2.0` 并加 `--audio-upload`。
新配置更新，App 下次刷新就拿到它；已经按 1.1 同意的人**不会**被上传录音（他们没同意过）。

研究参与默认不设时限；**要结束时**（研究者决定）：`python3 scripts/close_manifest.py <manifest_id>`

**取数**
- 前后测对比：`backend/analysis/thesis.sql` 第 11 段（改成新的 study_id）。
- 全部研究表：`scripts/export_research.py`；`attempts.csv` 里 `field_session_id` 非空的就是实测。
- 录音（受限数据，只导到本机，不进仓库与附件）：
  `python3 scripts/export_recordings.py <manifest_id> --out <本机目录>`。

**解释边界**：自愿参加者的单组前后测，测试词与训练词不同；可描述变化，不能写成训练的因果效果。

**App Store**：开录音时，App Store Connect 的「App 隐私」要补报「音频数据」（研究用途、
与身份不关联）；隐私政策已改为如实说明（docs/privacy-policy.html，同时更正了服务器所在地：美国）。

## B. 发版与旧数据（沿用）

## 0. 一次性
- 后端已上线：`https://pinyintone-backend.onrender.com`（Render + Neon）；iOS 已通过 `APIConfig.plist` 连接。
- 签名 Team、麦克风说明、出口合规、App 图标均已配好。

## 1. 发版（每次更新）
1. Xcode 选 **Any iOS Device** → **Product → Archive**。
2. Organizer → **Distribute App → App Store Connect → Upload**。
3. **每次上传前把 build 号 +1**（target → General → Build；本轮改版是 2.0 (20)——
   App Store 上在售的是 1.0，所以这次必须升营销版本号）。
   研究配置绑定构建号：换了构建号，要么新冻结一份配置，要么把新号加进 `--compatible-builds`。
4. App Store Connect → **TestFlight**：等构建处理完 → 填测试信息 → 加测试组/被试邮箱。
   - 内部测试：即时、免审；外部测试：首个构建过一次快速 Beta 审核。

## 2. 反馈呈现（已取消 A/B，无需发码）
- **不再有 A/B 分组**。训练时有两种显示方式——颜色块 / 音高曲线——
  由学习者自己在设置里切换，默认音高曲线。两种通关标准一样。
- ⚠ `feedback_mode` 记的是"当时屏幕上是哪种"，但它是**自选**的：
  **不要**拿它做组间比较（想看曲线的人本来可能就更投入，属自选择偏差）。
- 词集：普通练习可以练全部声调词条；`set1` / `set2` / `assessment` 只是历史标签，
  不再影响出题。自测词与练习词可以重叠，自测记录里带着该词此前练过几次。
- 你**不用发任何码**——直接用被试注册时填的 **名字（nickname）** 对应数据。
- 取数注意：`schema_version >= 5` 起 `grade` 不是 `dtw_score` 的纯函数——
  全一声的词若掉调超过 3 个半音会被走向闸门判 `fail`（DTW 判不出这种错）。
  **判通关一律用 `grade`**，不要用 `dtw_score <= 0.5` 重算；
  `grade = 'fail' AND dtw_score <= 0.5` 即被闸门拦下的记录。
- 取数注意：`schema_version >= 4` 的分数用**带下限的归一化**。此前纯 z-score 对平调退化，
  一声词读得越平分数越差（详见 `docs/LEVEL_TONE_SCORING.md`）。
  **含一声的词不可与 ≤3 的记录混合分析**；不含一声的词除数不变，分数逐位一致。
- 取数注意：`schema_version >= 3` 的 `feedback_mode` 是**学习者自选**的显示模式
  （裸测阶段为空）；`schema_version < 3` 的同名值是当年**随机分配**的实验条件。
  两者语义不同，**不可混在一起分析**，且 v3 的自选值不可用来做组间比较。

## 2b. 普通练习与可选自测（已取代三阶段）
- 进「声调练习」直接就是普通练习：有反馈，可选词、换词、重录，随时退出。
  **没有前测，没有「练遍才能解锁」。** 已安装的用户升级后也不会被旧的前测进度挡住。
- 自测在声调页右上角的「…」菜单里，由学习者主动开始，可随时退出。
  自测不显示分数、曲线、示范或建议，做完只说「录完了」。
- 旧业务表的 `phase`：普通练习写 `training`，自测写 `self_test`。
  历史上的 `pretest` / `posttest` 行不再产生。
  （注意区分：`phase` 是记录的类型，`stage1/2/3` 是关卡编号。）

## 3. 被试操作（发 PARTICIPANT_GUIDE.md 给他们）
装 App → 选语言 → 选「我是学生」→ 用 Apple 账号登录（名字可留空）→ 直接练习。
是否参加研究由他们在首页或设置里自己决定。

## 4. 监测数据是否进库
随时跑冒烟（确认后端在线）：
```bash
python3 backend/scripts/smoke.py https://pinyintone-backend.onrender.com
```
全 200 即正常。（Render 免费版闲置休眠，首请求冷启动 ~30–60s。）

## 5. 取旧业务表的历史数据
> 新版研究数据请用 A5 / A6 的 `export_research.py`。本节只针对旧业务表。

Neon 控制台 SQL Editor，逐段运行 `backend/analysis/export.sql`，右上角 **Download as CSV**：
- 第 1 段：原始声调长表（含 phase / word_set_id / 质量与版本字段）。
- 第 3 段：历史上的前测 / 后测记录。**新版不再产生这类记录**，这一段只对旧数据有内容。
- 第 4 段：数据质量自查（quality_flag / result_status / 参照来源分布）。

或本地：
```bash
psql "<NEON_DATABASE_URL>" -c "\copy (粘贴某段 SELECT) TO 'out.csv' WITH CSV HEADER"
```

## 6. 关键参数（论文写作参考，见 CLAUDE.md）
- 采样率 16 kHz；YIN 75–500 Hz / 阈值 0.15；DTW 通关线 ≤ 0.5（展示为 ≥60 分）。
- 送气：底噪 + 15 dB 阈值，触发率 ≥ 0.6 通关。
- 母语者参照：当前用系统 TTS（zh-CN）合成 F0；可后续替换真人录音。
- 反馈呈现：已取消 A/B，训练阶段有两种显示方式，由被试自选。每条记录带
  `phase`、`word_set_id`、`assessment_set_version`、`result_status`、
  `schema_version`、`app_version`。
  `feedback_mode` **仍在写**，记的是该条记录当时屏幕上是哪种显示（裸测为空）——
  但它是自选的，**不得当实验条件做组间比较**（见上文 §2）。
  `presentation_order` / `users.experiment_group` / `users.counterbalance_index`
  已停止写入，**分析新数据时不要使用**。

## 6b. 技术性失败（录音没录上）
- 没录上的尝试**会入库**，标记 `result_status = 'technical_retry'`，
  并带匿名的 `failure_reason`（权限被拒 / 有声帧过少 / 录音中断 / 信号质量差）。
- 这类行**没有发音成绩**：`dtw_score = -1`、`grade = 'n/a'` 只是占位哨兵。
  ⚠ 算任何分数前必须先筛掉，否则 -1 会被当成满分把均值拉低
  （`export.sql` 各段已统一处理）。
- 它们也**不计入**"这个词练过没有"。
- 用途：看失败率和失败原因分布，判断数据质量与设备/权限问题——
  见 `export.sql` 第 4 段的 `pct_technical_retry`。

## 7. 结果解释边界（写论文务必遵守）
- DTW 分数、等级、通关率、触发率都是**形成性反馈与应用日志指标**，
  **不是**语言能力等级，不得直接当作声调习得效果的证据。
- 本轮是小样本的应用与可用性研究：没有前后测实验，没有对照组。
  自选的自测和自选的反馈模式都**不能**用来论证教学效果。
- 参与者人数按研究编号去重后如实报告；「可招募 10 人」不等于「已采集 10 人」。
- 没有成功参与、没有作答、没有传到服务器，是三种不同的情况，分别统计。
