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
- 取数注意：`schema_version >= 3` 的记录一律是动态曲线；带
  `staticColor` / `dynamicF0` 的是取消分组之前的历史数据，**不可与新数据混在一起比较**。

## 2b. 阶段流转（前测 → 训练 → 后测）
- 被试首次进「声调训练」自动从 **前测** 开始：固定 4 词各录一遍，
  **不显示分数/等级/颜色/曲线**，录完自动进下一题。
- 前测走完自动转入 **训练**：显示条件 A 或 B 的反馈，可自由重录/换词。
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
- 反馈呈现：已取消 A/B，唯一方式是动态 F0 可视化。每条记录带
  `phase`、`word_set_id`、`assessment_set_version`、`result_status`、
  `schema_version`、`app_version`。
  `feedback_mode` / `presentation_order` / `users.experiment_group` /
  `users.counterbalance_index` 均已停止写入，**分析新数据时不要使用**。

## 7. 结果解释边界（写论文务必遵守）
- DTW 分数、等级、通关率、触发率都是**形成性反馈与应用日志指标**，
  **不是**语言能力等级，不得直接当作声调习得效果的证据。
- 代码支持前测/训练/后测三阶段 **≠** 已完成前测/训练/后测实验；
  当前阶段只有真实应用日志，报告中须如实说明。
