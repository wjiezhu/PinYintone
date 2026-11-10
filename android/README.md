# Pinyintone Android

原生 Kotlin + Jetpack Compose。与 iOS 版同仓库；后端共用 `backend/`。

当前阶段：**评分核心**（已用 Swift 版对照数据锁住）+ **声调普通练习与可选自测**（录音链路、界面、本地存储）
+ **直接分发准备**（正式签名、新版本提示、诊断信息页）。
登录、上传同步、研究流程、送气练习、自由文本、教师端都还没做。

## 工程结构

```
android/
├── settings.gradle.kts       # 有 Android SDK 才纳入 :app；没有时只配置 :core
├── gradle/libs.versions.toml # 依赖白名单（见下）
├── build-logic/              # 构建期工具（纯 JVM）：iOS 字符串 → Android 资源；复制共用语料
├── core/                     # 纯 JVM，不依赖 Android —— 评分与练习逻辑，测试几秒跑完
│   └── src/main/kotlin/joy/pinyintone/core/
│       ├── audio/
│       │   ├── AudioFramer.kt        ← AudioFramer.swift（+ AudioEngine.floatSamples）
│       │   ├── F0Extractor.kt        ← F0Extractor.swift（YIN / clean / 带下限的 normalize）
│       │   ├── DTWAnalyzer.kt        ← DTWAnalyzer.swift（含 FeedbackGrade）
│       │   ├── ToneDirectionGate.kt  ← ToneDirectionGate.swift
│       │   ├── AspirationDetector.kt ← AspirationDetector.swift
│       │   ├── ToneContour.kt        ← ToneContour.swift
│       │   ├── ReferenceShaper.kt    ← SpeechService.swift 的参照整形
│       │   ├── ToneScorer.kt         ← ToneTrainingViewModel.stopRecordingAndEvaluate() 的计算部分
│       │   ├── Resampler.kt          # 硬件采样率 → 16 kHz（AudioRecord 16 kHz 起不来时用）
│       │   ├── PcmChunker.kt         ← AudioEngine 的格式转换与 1600 采样分片
│       │   └── Wav.kt
│       ├── practice/
│       │   ├── TonePracticeSession.kt ← ToneTrainingViewModel 的状态机与记录逻辑（普通练习 / 自测）
│       │   ├── TrainingRecord.kt      ← SyncDTOs.swift 的 TrainingSessionDTO（键名有测试核对）
│       │   ├── RecordSchema.kt        ← RecordSchema.swift / TrainingPhase / FeedbackStyle
│       │   ├── FeedbackScore.kt       ← FeedbackResult.score（百分制显示分）
│       │   └── ChartGeometry.kt       ← ModeB_F0WaveformView 的取点
│       ├── corpus/Corpus.kt           ← CorpusLoader.swift / Lexeme.swift
│       ├── theme/ThemeTokens.kt       ← Theme.swift 的色值（有测试逐个核对）+ 对比度计算
│       └── json/Json.kt
└── app/                      # Compose，minSdk 26，applicationId joy.pinyintone（参照 iOS 的 Joy.PinYintone）
    ├── ios-strings.keys       # 从 iOS 取哪些界面文字
    └── src/main/java/joy/pinyintone/app/
        ├── audio/AudioRecorder.kt   # AudioRecord → PcmChunker → AudioFramer → YIN
        ├── audio/SamplePlayer.kt    # 「听示范」（系统 TTS，只播放）
        ├── data/Storage.kt          # Room（training_records）+ SharedPreferences
        └── ui/…                     # 主题、练习页、自测、曲线、颜色模式
```

命名、结构、注释尽量与 Swift 一一对应，每个文件头注明对应的 Swift 文件。**改评分要两边一起改**，
然后按 `testdata/scoring/README.md` 重新生成对照数据。

### 两端共用的源头（不另存一份）

| 内容 | 源头 | Android 怎么拿 |
|------|------|----------------|
| 语料 | `PinYintone/Resources/Corpus/lexemes.json` | 构建时 `copySharedCorpus` 复制进 assets；core 测试直接读 |
| 界面文字（中英法阿；西班牙语只有 Android，源文件在 `android/app/localizations/es.lproj`，只含白名单里的键，不放进 iOS 的 Localizations 以免 App Store 把它列成 iOS 支持的语言） | `PinYintone/Resources/Localizations/*/Localizable.strings` | 构建时 `generateIosStrings` 按 `app/ios-strings.keys` 生成 `strings_ios.xml`；缺译或占位符不一致即构建失败 |
| 颜色 token | `PinYintone/Core/UI/Theme.swift` | 色值抄在 `ThemeTokens.kt`，测试解析 Theme.swift 逐个核对 |
| 词序、记录字段、schemaVersion | `CorpusLoader.swift` / `SyncDTOs.swift` / `RecordSchema.swift` | 抄在 Kotlin 里，测试解析 Swift 文件核对 |

Android 独有的文字（TTS 没有中文语音时的提示等）写在 `app/src/main/res/values*/strings.xml`，五种语言（英、中、法、阿、西）都要写。

## 声调练习（本阶段）

- **录音**：`AudioRecord`，单声道 PCM16，音源 `VOICE_RECOGNITION`。优先 16 kHz；初始化失败就用硬件采样率，
  由 `Resampler` 降到 16 kHz。之后与 iOS 同一条路：1600 采样一片 → 帧化 512 / 128 → YIN。
  点一下开始、再点一下停止；录音键在任何状态下位置不动。原始录音只在内存里流过。
- **启动失败不静默**：权限没给、设备起不来、中途被打断（API 29+ 用录音静音回调识别来电 / 抢占）、切到后台，
  都给出能照着做的提示，并落一条 `technical_retry` 记录（`dtwScore = -1`、`grade = "n/a"`，不增加尝试次数）。
- **麦克风权限**：首次点录音时先用 App 语言说明用途，再弹系统框；拒绝后失败块里给「打开设置」；
  被永久拒绝（系统不再弹框）同样给设置入口；从设置回来自动重查，不用重启。
- **参照曲线**：词条有 `audioFilename` 时读 `assets/reference/<文件名>`（16 kHz WAV，`ReferenceShaper.f0Track`，
  不做下倾矫正），记 `reference_type = real`；没有就用理想轮廓，记 `ideal`。**不用系统 TTS 生成评分参照**。
- **听示范**：系统 TextToSpeech，只播放。没有中文语音时提示并给出系统设置入口。
  「示范开始播放」只在引擎的 `onStart` 回调里报（研究事件以后挂在这里）。
- **两种显示模式**：曲线（默认）/ 颜色，学习者随时切换，录音中禁用；通关标准一致，只影响记录里的 `feedbackMode`。
- **自测**：右上角菜单里主动开始，可随时退出；录完不显示任何分数、等级、颜色、曲线、示范或建议，后台照常算分入库
  （`phase = self_test`、`feedbackMode = null`、`assessmentSetVersion = assess-v1`）。
- **本地存储**：Room 表 `training_records`，列与 iOS 上报的 `TrainingSessionDTO` 一一对应，`synced = false`。本阶段不上传。
- **阿拉伯语界面**：汉字、拼音、曲线、颜色模式的音节格、操作栏、分数强制左到右，其余随系统镜像。

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

```bash
cd android && ./gradlew -p build-logic test
```

都是纯 JVM，不需要 Android SDK，几秒跑完。对照测试每类比较的实际最大误差写在 `core/build/reports/golden-diff.txt`。

有 SDK 时编 App：

```bash
cd android && ./gradlew :app:assembleDebug
```

## 在模拟器上跑

本机 SDK 在 `~/Library/Android/sdk`（`android/local.properties` 写 `sdk.dir`，该文件不入库）。
两个模拟器：`pt_api26`（API 26，无 Google 服务，接近国内手机）、`pt_api37`（API 37，Google APIs）。

```bash
cd android && ./gradlew :app:assembleDebug
```

```bash
~/Library/Android/sdk/emulator/emulator -avd pt_api26 -no-window -no-audio -gpu swiftshader_indirect
```

```bash
~/Library/Android/sdk/platform-tools/adb install -r app/build/outputs/apk/debug/app-debug.apk
```

模拟器里没有人声。调试构建可以用**合成麦克风**走通整条链路（48 kHz 合成目标词的理想轮廓，
经过与真实麦克风相同的重采样 → 分片 → 帧化 → YIN）：

```bash
~/Library/Android/sdk/platform-tools/adb shell am start -n joy.pinyintone/joy.pinyintone.app.MainActivity --es pt_mic tones
```

`pt_mic` 可取 `tones`（按目标声调读）、`flat`（读成平调）、`silent`（只有静音 → 技术失败）。
正式包（release）不读这个参数；`r8check` 包读（见「正式版安装包」）。

坑：本机在后台无窗口启动模拟器时，开着宿主音频会让模拟器启动即退出，所以用 `-no-audio`；
这时真实麦克风录到的是静音（App 正确提示「没录到声音」）。手写的 AVD 配置要有 `hw.mainKeys=no`，
否则 API 26 的 SystemUI 会反复崩溃。

## 正式版安装包（直接分发，不上 Google Play）

摩洛哥与中国两路都用「下载链接 + 二维码」发安装包。安装说明给参与者看 `docs/ANDROID_INSTALL_GUIDE.md`，
试用清单见 `docs/ANDROID_PILOT_CHECKLIST.md`。

### 签名

- 正式签名证书**在仓库之外**：`~/.pinyintone-release/pinyintone-release.jks`（PKCS12，RSA 4096，有效期到 2054 年，别名 `pinyintone`），
  密码在同目录的 `signing.properties`（权限 600）。证书 SHA-256：
  `78:4F:36:C9:5D:37:06:68:CF:6B:75:C9:06:F5:20:28:1C:C2:A5:F2:2B:0A:E0:81:48:27:1F:70:E5:6B:43:22`
- **必须离线备份整个目录**（密码管理器 + 加密 U 盘各一份）。Android 只接受同一证书签名的更新：
  证书或密码丢了，已装的学生就再也收不到更新，只能卸载重装——而卸载会删掉手机里没上传的记录。
- Gradle 读签名配置的顺序：环境变量 `PT_RELEASE_STORE_FILE` / `PT_RELEASE_STORE_PASSWORD` / `PT_RELEASE_KEY_ALIAS` /
  `PT_RELEASE_KEY_PASSWORD`；或 properties 文件，路径来自环境变量 `PT_SIGNING_PROPERTIES` 或
  `android/local.properties` 里的 `pinyintone.signing.properties=<路径>`。都没有时 release 能配置、能 lint，
  **打包那一步报错**，不会产出未签名的包。`*.jks`、`signing.properties` 等已在 `.gitignore` 里。

### 打包

```bash
cd android && ./gradlew :app:assembleRelease
```

产物 `app/build/outputs/apk/release/app-release.apk`，R8 映射文件在 `app/build/outputs/mapping/release/`（每个发出去的版本都存一份）。
发新版前改 `app/build.gradle.kts` 的 `versionCode`（必须递增）与 `versionName`。

- **后端地址**：正式包固定连 `https://pinyintone-backend.onrender.com`，不连任何测试地址，也不允许明文 http。
  本地验证可以 `-Ppt.apiBaseUrl=http://10.0.2.2:8765` 临时打一份（只有这时才放开明文 http）——这样的包**不得分发**，
  验证完不带参数重新打包。
- **R8**：开启压缩与混淆。评分不用反射，Room 用自带规则。`r8check` 构建类型与 release 走完全相同的 R8，
  但用调试密钥签、允许合成麦克风，用来在模拟器上确认混淆后评分与 Room 照常：

```bash
cd android && ./gradlew :app:assembleR8check
```

### 新版本提示

App 启动时请求一次 `GET /api/app-version/android`（值来自后端的 `ANDROID_*` 环境变量，见 `backend/README.md`）。
失败静默；有新版本时练习页顶部出现可关闭的提示（关掉的那个版本不再提示）；低于最低支持版本时提示关不掉，
但**练习照常**（CLAUDE.md 禁令 19）。下载链接只放行 https，交给系统浏览器打开，App 内不下载、不安装。

### 诊断信息

设置 → 诊断信息：App 版本、厂商型号、Android 版本、录音实际采样率与是否降采样、音源、最近一次录音的有声帧数与结果状态、
中文 TTS、界面语言、字号缩放、上次新版本检查的结果。可复制、可调系统分享。复制出去的是固定英文键名的文本，
不含录音、词条、分数、deviceID 或任何身份信息。

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
