# Pinyintone 研究操作手册（一页纸）

从发版到取数据的完整流程。详细部署见 `DEPLOY.md`，被试说明见 `PARTICIPANT_GUIDE.md`。

## 0. 一次性
- 后端已上线：`https://pinyintone-backend.onrender.com`（Render + Neon）；iOS 已通过 `APIConfig.plist` 连接。
- 签名 Team、麦克风说明、出口合规、App 图标均已配好。

## 1. 发版（每次更新）
1. Xcode 选 **Any iOS Device** → **Product → Archive**。
2. Organizer → **Distribute App → App Store Connect → Upload**。
3. **每次上传前把 build 号 +1**（target → General → Build；当前已是 2）。
4. App Store Connect → **TestFlight**：等构建处理完 → 填测试信息 → 加测试组/被试邮箱。
   - 内部测试：即时、免审；外部测试：首个构建过一次快速 Beta 审核。

## 2. 反馈呈现（已取消 A/B，无需发码）
- **不再有 A/B 分组**。训练时有两种显示方式——颜色块 / 音高曲线——
  由学习者自己在设置里切换，默认音高曲线。两种通关标准一样。
- ⚠ `feedback_mode` 记的是"当时屏幕上是哪种"，但它是**自选**的：
  **不要**拿它做组间比较（想看曲线的人本来可能就更投入，属自选择偏差）。
- 词集：训练池（10 词）与固定测试词集 `assessment`（4 词）不重叠；
  前测与后测共用测试词集。`set1` / `set2` 只是历史标签，不再影响出题。
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

## 2b. 阶段流转（前测 → 训练 → 后测）
- 被试首次进「声调训练」自动从 **前测** 开始：固定 4 词各录一遍，
  **不显示分数/等级/颜色/曲线**，录完自动进下一题。
- 前测走完自动转入 **训练**：显示被试自选的那种反馈，可自由重录/换词。
- 训练词集里每个词都练过至少一次后，训练页出现「开始后测」按钮，
  由你或被试主动点击进入 **后测**（与前测同一份测试词集，同样不显示反馈）。
- 三个阶段的 `phase` 随每条记录上报，取数时按它筛选。
  （注意区分：`phase` 是研究阶段，`stage1/2/3` 是关卡编号。）

## 3. 被试操作（发 PARTICIPANT_GUIDE.md 给他们）
装 TestFlight → 装 App → 允许麦克风 → 选「我是学生」→ **填名字** → 三关卡练习。

## 4. 监测数据是否进库
随时跑冒烟（确认后端在线）：
```bash
python3 backend/scripts/smoke.py https://pinyintone-backend.onrender.com
```
全 200 即正常。（Render 免费版闲置休眠，首请求冷启动 ~30–60s。）

## 5. 取数据 / 统计
Neon 控制台 SQL Editor，逐段运行 `backend/analysis/export.sql`，右上角 **Download as CSV**：
- 第 1 段：原始声调长表（含 phase / word_set_id / 质量与版本字段）→ R 混合模型 / 学习曲线。
- 第 3 段：★ 前测 vs 后测（固定测试词集）→ 增益比较。
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
- 它们也**不计入**"这个词练过没有"，所以不会影响后测解锁。
- 用途：看失败率和失败原因分布，判断数据质量与设备/权限问题——
  见 `export.sql` 第 4 段的 `pct_technical_retry`。

## 7. 结果解释边界（写论文务必遵守）
- DTW 分数、等级、通关率、触发率都是**形成性反馈与应用日志指标**，
  **不是**语言能力等级，不得直接当作声调习得效果的证据。
- 代码支持前测/训练/后测三阶段 **≠** 已完成前测/训练/后测实验；
  当前阶段只有真实应用日志，报告中须如实说明。
