# Pinyintone Android

原生 Kotlin + Jetpack Compose。与 iOS 版同仓库；后端共用 `backend/`。

当前阶段：**评分核心已移植并用 Swift 版的对照数据锁住**；App 只有一个占位页面。
录音、界面、登录、同步、研究流程都还没做。

## 工程结构

```
android/
├── settings.gradle.kts      # 有 Android SDK 才纳入 :app；没有时只配置 :core
├── gradle/libs.versions.toml # 依赖白名单（见下）
├── core/                    # 纯 JVM 模块，不依赖 Android —— 评分核心
│   └── src/main/kotlin/joy/pinyintone/core/audio/
│       ├── AudioFramer.kt         ← PinYintone/Core/Audio/AudioFramer.swift（+ AudioEngine.floatSamples）
│       ├── F0Extractor.kt         ← F0Extractor.swift（YIN / clean / 带下限的 normalize）
│       ├── DTWAnalyzer.kt         ← DTWAnalyzer.swift（含 FeedbackGrade）
│       ├── ToneDirectionGate.kt   ← ToneDirectionGate.swift
│       ├── AspirationDetector.kt  ← AspirationDetector.swift（+ AspirationViewModel 里的 5 片校准 / 6 片窗口常量）
│       ├── ToneContour.kt         ← ToneContour.swift
│       ├── ReferenceShaper.kt     ← SpeechService.swift 的参照整形（f0Track / smoothReference / removeExcessDeclination /
│       │                             blendTowardIdeal / contourContradictsTones）
│       ├── ToneScorer.kt          ← ToneTrainingViewModel.stopRecordingAndEvaluate() 的计算部分
│       └── Wav.kt                 # 读 16-bit / 单声道 / 16 kHz WAV
└── app/                     # Compose，minSdk 26，applicationId joy.pinyintone（参照 iOS 的 Joy.PinYintone）
```

命名、结构、注释尽量与 Swift 一一对应，每个文件头注明对应的 Swift 文件。**改评分要两边一起改**，
然后按 `testdata/scoring/README.md` 重新生成对照数据。

## 环境

- JDK 17（`brew install openjdk@17`，然后 `export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home`）
- Gradle 用仓库里的 wrapper（8.14.3），不需要单独装
- 编 `:app` 需要 Android SDK（compileSdk 35）：装 Android Studio，或命令行工具后
  `sdkmanager "platforms;android-35" "build-tools;35.0.0"`，并在 `android/local.properties` 写 `sdk.dir=...`。
  没有 SDK 时 `:app` 不参与构建，`:core` 照常

## 跑测试

```bash
cd android && ./gradlew :core:test
```

纯 JVM，几秒跑完。每类比较的实际最大误差写在 `core/build/reports/golden-diff.txt`。

有 SDK 时编 App：

```bash
cd android && ./gradlew :app:assembleDebug
```

## 对照测试与容差

`ScoringGoldenTest` 读 `testdata/scoring/` 里 Swift 生成的 WAV 与 `golden.json`，分两层比：

1. **逐步**：把 Swift 的中间结果喂给对应的 Kotlin 函数。只用 Float 逐元素运算的步骤
   （clean、DTW、分段分数、参照平滑 / 去下倾 / 混合、矛盾判定、送气触发率）要求**逐位一致**，
   实测也是逐位一致。
2. **端到端**：Kotlin 从 WAV 自己算到底，与 Swift 的最终结果比。

**判定类结果一律完全一致**：每帧有声 / 无声、有声帧数、技术重录、闸门是否拦下、grade、是否通关、
送气每片是否触发与第几片通关。

浮点值的容差与理由：

| 量 | 容差 | 理由 |
|----|------|------|
| F0（Hz，端到端） | 1e-3 + 2e-5 × 值 | Swift 的 YIN 差分函数用 `vDSP_svesq` 求和，求和顺序未公开，无法逐位复现；Kotlin 用 Double 累加。实测最大差 3e-5 Hz。2e-5 的相对误差远低于 1 音分（≈ 6e-4），听觉上不存在 |
| 归一化值、DTW、分段分数、半音、dB（端到端） | 1e-4 + 1e-4 × 值 | 同上，`vDSP_meanv` / `vDSP_svesq` / `vDSP_rmsqv` 的求和顺序。实测最大差 4e-6（归一化）、4e-7（DTW）。离通关线 0.5 的任何实际分数都不会因 1e-4 翻转 |
| 经 libm / Accelerate 的单步（normalize、`pow`、`log2`） | 1e-5 + 1e-6 × 值 | Kotlin 的 `pow` / `log2` / `sin` 经 Double 计算再转 Float，与 Apple 的 `powf` / `log2f` / `sinf` 可能差 1 ulp |

与 Swift 不逐位一致的地方只有上面这几类向量归约和数学库函数，**判定逻辑没有差异**。
当然，若某次真实录音的分数恰好落在 0.5 ± 1e-6 之内，两端可能判得不同——概率可忽略，
但真要发生，以「两端同一份音频重算」的方式复核即可。

## 继承自 CLAUDE.md 的约束

CLAUDE.md 是两端共同的约束，本工程全部继承（不在这里改 CLAUDE.md）。与 Android 直接相关的：

- **音频与评分参数不得改动**：16 kHz、帧长 512、帧移 128、Hann 窗；YIN 75–500 Hz、阈值 0.15、
  无声帧填 0 不插值；DTW 欧氏距离、通关线 ≤ 0.5；归一化 `(x - mean) / max(sd, mean × 0.03)`；
  全一声词首末下滑 > 3 半音不通关；送气底噪 + 15 dB、触发率 ≥ 0.6。`ScoringGoldenTest.lockedParametersMatchSwift` 会核对。
- **禁止 44.1 / 48 kHz 采样**（禁令 1）；录音时让硬件跑原生采样率，再自己降到 16 kHz（对应 iOS 禁令 12 的思路）
- **零第三方依赖**（禁令 5）：只用 Kotlin 标准库、AndroidX / Compose、测试用 JUnit；评分不引任何库
- **归一化下限不得删、不得改成固定 Hz**（禁令 13 / 14）；**闸门喂原始 Hz**、**只管全一声的词**（禁令 15 / 16）
- **技术性失败不计入成绩**（禁令 9）：`ToneScorer` 返回 `TechnicalRetry`，没有分数与等级；
  旧业务表写哨兵 `dtwScore = -1` / `grade = "n/a"`，**不写 0**；研究表写 NULL（禁令 23）
- **录音启动失败不得静默**（禁令 11）
- **自测不呈现任何评价性反馈**（禁令 6）；普通练习与自测同一套算法
- **两种显示模式是自选偏好，不是 A/B 分组**（禁令 2 / 10）
- **没有前测 → 训练 → 后测的强制流程**（禁令 19）
- 研究采集：服务端确认纳入前不产生研究日志；研究身份按账号而非设备（禁令 20–22）
- 结果解释：DTW / 等级 / 通关是形成性反馈，不是语言能力等级
- 界面：颜色只用语义 token、参考曲线实线 / 学习者曲线虚线、横轴不按音节分段（禁令 24 / 25）
- `schemaVersion` / `appVersion` 随每条记录上报，语义与 iOS 相同

Android 自己的约定（已定方案）：最低 API 26；ICU 拼音与分词只在 API 29+ 用，自由文本关卡在 Android 10 以下不显示；
只用 Google 登录；第一版不做教师端。
