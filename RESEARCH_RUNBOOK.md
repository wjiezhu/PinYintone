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

## 2. 分组（无需发码）
- 被试注册（填名字）时，**后端均衡随机分配** A/B（分到当前人数较少的组，等量随机），两组自动均衡；幂等（同设备重注册不变组）。
- 你**不用发任何码**，也不用维护"码↔人"对照——直接用被试注册时填的 **名字（nickname）** 对应数据。

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
- 第 5 段：每被试合并主表 → 受试间 t 检验 / ANCOVA。
- 第 6 段：A/B 组别描述统计（mean / sd / 通关率）。
- 第 1/2 段：原始长表 → R 混合模型 / 学习曲线。
- 第 7 段：学习增益（首次 vs 末次 DTW）。

或本地：
```bash
psql "<NEON_DATABASE_URL>" -c "\copy (粘贴某段 SELECT) TO 'out.csv' WITH CSV HEADER"
```

## 6. 关键参数（论文写作参考，见 CLAUDE.md）
- 采样率 16 kHz；YIN 75–500 Hz / 阈值 0.15；DTW 通关线 ≤ 0.5（展示为 ≥60 分）。
- 送气：底噪 + 15 dB 阈值，触发率 ≥ 0.6 通关。
- 母语者参照：当前用系统 TTS（zh-CN）合成 F0；可后续替换真人录音。
- 分组：注册时后端均衡随机分配（人少进哪组），离线本地随机兜底；存 `users.experiment_group` 与每条记录的 `group_assignment`。
