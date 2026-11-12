# 评分对照数据（iOS ↔ Android 共用）

这里的东西用来保证两端**分数可比**：同一段音，iOS（Swift）和 Android（Kotlin）
算出来的 F0、归一化序列、DTW 分数、闸门结果、grade、送气触发率必须一致。

| 文件 | 内容 |
|------|------|
| `*.wav` | 固定输入。16-bit PCM、单声道、16 kHz（CLAUDE.md 锁定采样率） |
| `golden.json` | Swift 版对这些输入的全部输出，**以 Swift 为准**。勿手改 |

`golden.json` 与 WAV 都由 iOS 单元测试
[`PinYintoneTests/Golden/ScoringGoldenTests.swift`](../../PinYintoneTests/Golden/ScoringGoldenTests.swift) 生成。
Android 侧由 [`android/core/src/test/.../ScoringGoldenTest.kt`](../../android/core/src/test/kotlin/joy/pinyintone/core/audio/ScoringGoldenTest.kt) 读取比对。

## 内容

**声调用例**（`toneCases`）——每例都有：逐帧 F0（`f0Raw`）、clean 后（`f0Clean`）、
有声帧数、理想轮廓参照（`referenceNormalized`）、归一化后的学习者序列、DTW 分数、
逐字分段分数、走向闸门（`gate`：`applies` / `fallSemitones` / `fails`）、
走势幅度闸门（`contourGate`：`applies` / `spanSemitones` / `fails`，v8 起；`spanSemitones` 即记录里的 `pitchSpanSemitones`）、
`grade`、`passed`、`resultStatus`；
以及把同一段音当作「母语者 / TTS 参照」时的整形各步（`referenceShaping`：
`smoothed` → `deDeclined` → `blended` → `contradicts`，以及 `f0Track` 带声调 / 不带声调的最终结果）。

覆盖：一声读平带微小抖动（归一化下限）、男声低音域一声、一声一路下滑（闸门拦下而 DTW 在线内）、
带句调下倾的一声（去下倾）、二声、四声、三声曲折、二声 + 四声带无声间隔、四声读平、
声调与走向矛盾（参照整形判矛盾）、有声帧不足与纯底噪（技术性重录）；
v8 加了走势幅度闸门的用例：四声读平带 1.5 半音下倾（DTW 在线内、闸门拦下）、2+4 读平、
3+2 走势压缩到约 3 半音（闸门放行）、1+5 读平（两道闸门都不适用）、
2+4 只录到一个字（跨度不足被拦——已知风险边界，见 `docs/SCORING_FLAT_READING_STUDY.md`）。

**送气用例**（`aspirationCases`）——底噪段 + 气流段，按 App 的做法切 1600 采样一片，
前 5 片校准底噪，之后 6 片滑窗：底噪 dB、阈值 dB、每片是否触发、每片触发率、第几片通关。

**理想轮廓**（`toneContours`）——`ToneContour.ideal` 对 1–5 声、未知声调、多音节的输出与归一化。

## 两种运行模式

iOS 测试默认是**比对模式**：读这里已有的 WAV 重算，与 `golden.json` 在容差内比对。
它跟其它单元测试一起在 CI 上跑——Swift 评分一改、结果一变就会红，提醒同时改 Android 并重新生成。

## 重新生成

什么时候要重新生成：改了 Swift 评分代码（有意的）；换了参考音频；加了用例。

```bash
TEST_RUNNER_PINYINTONE_WRITE_GOLDEN=1 xcodebuild test -project PinYintone.xcodeproj -scheme PinYintone -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:PinYintoneTests/ScoringGoldenTests CODE_SIGNING_ALLOWED=NO
```

（`TEST_RUNNER_` 前缀是 xcodebuild 把环境变量传进测试进程的方式；测试里读的是 `PINYINTONE_WRITE_GOLDEN`。）
生成模式会**重新合成全部 WAV** 并覆盖 `golden.json`。之后：

1. 再跑一次不带该变量的同一条命令，确认比对模式通过；
2. 跑 Android 侧：`cd android && ./gradlew :core:test`；不过就说明两端分叉了，改 Kotlin 直到通过；
3. `git diff testdata/scoring/golden.json` 看清哪些数变了、是否符合预期，再提交。

单元测试宿主不连线上（`TestHost.isRunningUnitTests`），生成时不会把记录同步到线上库。

## 以后换成母语者参考音频

计划用母语者录的 20 个词替换合成参考（两端共用）。届时：

1. 把录音转成 16-bit PCM / 单声道 / 16 kHz WAV（两端的 WAV 读取只接受这个格式；
   重采样请离线做好，不要依赖各平台解码器——它们的重采样滤波器不同，会让两端输入就不一样）；
2. 放进本目录，在 `ScoringGoldenTests.swift` 里为每个词加一个「读已有 WAV、不合成」的用例
   （目前的用例都是合成的，生成模式会重写它们的 WAV；母语者录音不能被覆盖）；
3. 按上面的步骤重新生成并在两端跑通。
