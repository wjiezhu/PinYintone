import XCTest
@testable import PinYintone

/// 两端评分对照数据（iOS ↔ Android）。
///
/// 用一批固定输入跑 **Swift 版**评分全流程，结果写进 `testdata/scoring/golden.json`；
/// Android 的 `core` 模块读同一批 WAV 与 JSON 做对比（`ScoringGoldenTest.kt`）。
///
/// 两种模式：
/// - 默认（CI 里就是这种）：读仓库里已有的 WAV，重算，与 `golden.json` 在容差内比对。
///   Swift 评分代码一改、结果一变，这里就红——提醒同时改 Android 并重新生成对照数据。
/// - 生成：环境变量 `PINYINTONE_WRITE_GOLDEN=1`（xcodebuild 里写成
///   `TEST_RUNNER_PINYINTONE_WRITE_GOLDEN=1`）时，重新合成输入 WAV 并覆盖 JSON。
///   步骤见 `testdata/scoring/README.md`。
///
/// 这里的流程是 `ToneTrainingViewModel.stopRecordingAndEvaluate()` 计算部分的镜像
/// （那边与界面、入库写在一起，没法单独调）。那边改了，这里要跟着改。
@MainActor
final class ScoringGoldenTests: XCTestCase {

    // 勿删：见 CLAUDE.md 禁令 18（@MainActor 类的隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    // MARK: - 位置与模式

    private static let dataDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // Golden
        .deletingLastPathComponent()      // PinYintoneTests
        .deletingLastPathComponent()      // 仓库根
        .appendingPathComponent("testdata/scoring", isDirectory: true)

    private var writeMode: Bool {
        ProcessInfo.processInfo.environment["PINYINTONE_WRITE_GOLDEN"] == "1"
    }

    /// 容差：同一份 Swift 代码在不同机器 / 系统版本上，Accelerate 的向量归约可能换实现，
    /// 低位会有出入；超过这个量级就说明算法真的变了。与 Android 侧的理由见 README。
    private let absTolerance: Double = 1e-3
    private let relTolerance: Double = 1e-4

    private let f0 = F0Extractor()
    private let dtw = DTWAnalyzer()

    // MARK: - 用例

    func testScoringGolden() throws {
        if writeMode {
            try FileManager.default.createDirectory(at: Self.dataDir, withIntermediateDirectories: true)
            for c in Self.toneCases { try writeWav(c.render(), name: c.name) }
            for c in Self.aspirationCases { try writeWav(c.render(), name: c.name) }
        }

        let golden = try buildGolden()
        let jsonURL = Self.dataDir.appendingPathComponent("golden.json")

        if writeMode {
            try (golden.render(indent: 0) + "\n").write(to: jsonURL, atomically: true, encoding: .utf8)
            return
        }

        let data = try Data(contentsOf: jsonURL)
        let committed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        var problems: [String] = []
        compare(golden, committed, path: "$", problems: &problems)
        XCTAssertTrue(problems.isEmpty,
            "Swift 评分结果与 testdata/scoring/golden.json 不一致（前 20 处）：\n"
            + problems.prefix(20).joined(separator: "\n")
            + "\n若是有意改动评分：按 testdata/scoring/README.md 重新生成，并同步修改 Android 的 core 模块。")
    }

    // MARK: - 计算

    private func buildGolden() throws -> J {
        var toneOut: [J] = []
        for c in Self.toneCases {
            let pcm = try readWav(name: c.name)
            toneOut.append(scoreToneCase(c, pcm: pcm))
        }
        var aspOut: [J] = []
        for c in Self.aspirationCases {
            let pcm = try readWav(name: c.name)
            aspOut.append(scoreAspirationCase(c, pcm: pcm))
        }

        var contours: [(String, J)] = []
        for tones in [[1], [2], [3], [4], [5], [9], [1, 4, 2]] {
            let ideal = ToneContour.ideal(for: tones)
            contours.append((tones.map(String.init).joined(separator: ","), .obj([
                ("tones", .ints(tones)),
                ("idealHz", .floats(ideal)),
                ("normalized", .floats(f0.normalize(ideal))),
            ])))
        }

        return .obj([
            ("about", .str("Swift 版评分的对照输出。由 PinYintoneTests/Golden/ScoringGoldenTests.swift 生成，勿手改；见 README.md")),
            ("formatVersion", .int(1)),
            ("params", .obj([
                ("sampleRate", .int(16_000)), ("frameSize", .int(512)), ("hopSize", .int(128)),
                ("minF0", .float(f0.minF0)), ("maxF0", .float(f0.maxF0)),
                ("yinThreshold", .float(f0.yinThreshold)),
                ("normalizationFloorRatio", .float(F0Extractor.normalizationFloorRatio)),
                ("passThreshold", .float(0.5)),
                ("gateMaxFallSemitones", .float(ToneDirectionGate.maxFallSemitones)),
                ("contourGateMinSpanSemitones", .float(ToneContourSpanGate.minSpanSemitones)),
                ("contourGateMinVoicedFrames", .int(ToneContourSpanGate.minVoicedFrames)),
                ("minVoicedFrames", .int(Self.minVoicedFrames)),
                ("qualityFlagThreshold", .float(Self.qualityFlagThreshold)),
                ("aspirationChunk", .int(1600)), ("aspirationCalibrationChunks", .int(5)),
                ("aspirationWindowChunks", .int(6)), ("aspirationPassRate", .float(0.6)),
            ])),
            ("toneContours", .obj(contours)),
            ("toneCases", .arr(toneOut)),
            ("aspirationCases", .arr(aspOut)),
        ])
    }

    /// 镜像 `ToneTrainingViewModel`：minVoicedFrames / qualityFlagThreshold
    private static let minVoicedFrames = 5
    private static let qualityFlagThreshold: Float = 2.0

    private func scoreToneCase(_ c: ToneCase, pcm: [Int16]) -> J {
        // 录音链路：1600 采样一片 → AudioFramer（512 / 128）→ 逐帧 YIN
        var rawHz: [Float] = []
        let framer = AudioFramer()
        framer.onFrame = { [f0] frame in rawHz.append(f0.extract(frame: frame)) }
        var i = 0
        while i < pcm.count {
            framer.feed(Array(pcm[i..<min(i + 1600, pcm.count)]))
            i += 1600
        }

        let cleaned = f0.clean(rawHz)
        let voicedFrames = cleaned.filter { $0 != 0 }.count
        let reference = f0.normalize(ToneContour.ideal(for: c.tones))

        var fields: [(String, J)] = [
            ("name", .str(c.name)),
            ("wav", .str("\(c.name).wav")),
            ("note", .str(c.note)),
            ("tones", .ints(c.tones)),
            ("f0Raw", .floats(rawHz)),
            ("f0Clean", .floats(cleaned)),
            ("voicedFrames", .int(voicedFrames)),
            ("referenceNormalized", .floats(reference)),
        ]

        if voicedFrames < Self.minVoicedFrames {
            fields += [
                ("resultStatus", .str("technical_retry")),
                ("normalized", .null), ("dtwScore", .null), ("segmentScores", .null),
                ("gate", .null), ("contourGate", .null), ("grade", .null), ("passed", .null),
            ]
        } else {
            let normalized = f0.normalize(cleaned)
            let score = dtw.distance(reference: reference, candidate: normalized)
            let fall = ToneDirectionGate.fallSemitones(hzTrack: cleaned, tones: c.tones)
            let dropped = ToneDirectionGate.fails(hzTrack: cleaned, tones: c.tones)
            let span = ToneContourSpanGate.spanSemitones(hzTrack: cleaned)
            let flat = ToneContourSpanGate.fails(hzTrack: cleaned, tones: c.tones)
            let grade = (dropped || flat) ? .fail : dtw.grade(dtwScore: score)
            fields += [
                ("resultStatus", .str(score >= Self.qualityFlagThreshold ? "quality_flagged" : "valid_result")),
                ("normalized", .floats(normalized)),
                ("dtwScore", .float(score)),
                ("segmentScores", .floats(dtw.segmentScores(reference: reference, candidate: normalized,
                                                            nSegments: c.tones.count))),
                ("gate", .obj([
                    ("applies", .bool(ToneDirectionGate.applies(tones: c.tones))),
                    ("fallSemitones", fall.map(J.float) ?? .null),
                    ("fails", .bool(dropped)),
                ])),
                // v8 走势幅度闸门；spanSemitones 即记录里的 pitchSpanSemitones
                ("contourGate", .obj([
                    ("applies", .bool(ToneContourSpanGate.applies(tones: c.tones))),
                    ("spanSemitones", span.map(J.float) ?? .null),
                    ("fails", .bool(flat)),
                ])),
                ("grade", .str(grade.rawValue)),
                ("passed", .bool(grade != .fail)),
            ]
        }

        // 参照曲线整形（SpeechService）：把同一段音当作「母语者 / TTS 参照」跑一遍
        let speech = SpeechService.shared
        let smoothed = speech.smoothReference(cleaned)
        let deDeclined = speech.removeExcessDeclination(smoothed, tones: c.tones)
        let blended = speech.blendTowardIdeal(deDeclined, tones: c.tones)
        fields.append(("referenceShaping", .obj([
            ("smoothed", .floats(smoothed)),
            ("deDeclined", .floats(deDeclined)),
            ("blended", .floats(blended)),
            ("contradicts", .bool(speech.contourContradictsTones(blended, tones: c.tones))),
            ("trackWithTones", .floats(speech.f0Track(from: AudioEngine.floatSamples(from: pcm),
                                                      tag: "golden", tones: c.tones))),
            ("trackWithoutTones", .floats(speech.f0Track(from: AudioEngine.floatSamples(from: pcm),
                                                         tag: "golden", tones: []))),
        ])))
        return .obj(fields)
    }

    /// 镜像 `AspirationViewModel`：前 5 片校准底噪，之后每片进 6 片滑窗算触发率
    private func scoreAspirationCase(_ c: AspirationCase, pcm: [Int16]) -> J {
        var chunks: [[Float]] = []
        var i = 0
        while i + 1600 <= pcm.count {
            chunks.append(AudioEngine.floatSamples(from: Array(pcm[i..<(i + 1600)])))
            i += 1600
        }
        let detector = AspirationDetector()
        detector.calibrateBaseline(frames: Array(chunks.prefix(5)))

        var window: [[Float]] = []
        var detects: [Bool] = []
        var rates: [Float] = []
        var passedAt: Int?
        for (k, frame) in chunks.dropFirst(5).enumerated() {
            window.append(frame)
            if window.count > 6 { window.removeFirst() }
            let rate = detector.triggerRate(frames: window)
            rates.append(rate)
            detects.append(detector.detect(frame: frame))
            if rate >= 0.6, passedAt == nil { passedAt = k }
        }
        return .obj([
            ("name", .str(c.name)),
            ("wav", .str("\(c.name).wav")),
            ("note", .str(c.note)),
            ("baselineDB", .float(detector.baselineDB)),
            ("thresholdDB", .float(detector.thresholdDB)),
            ("detect", .arr(detects.map(J.bool))),
            ("triggerRate", .floats(rates)),
            ("passedAtChunk", passedAt.map(J.int) ?? .null),
        ])
    }

    // MARK: - 比对

    private func compare(_ mine: J, _ theirs: Any, path: String, problems: inout [String]) {
        switch mine {
        case .null:
            if !(theirs is NSNull) { problems.append("\(path): 应为 null，文件里是 \(theirs)") }
        case .bool(let b):
            guard let n = theirs as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID(), n.boolValue == b else {
                problems.append("\(path): \(b) ≠ \(theirs)"); return
            }
        case .int(let v):
            guard let n = theirs as? NSNumber, n.doubleValue == Double(v) else {
                problems.append("\(path): \(v) ≠ \(theirs)"); return
            }
        case .float(let f):
            guard let n = theirs as? NSNumber else { problems.append("\(path): 应为数，文件里是 \(theirs)"); return }
            let a = Double(f), b = n.doubleValue
            if abs(a - b) > absTolerance + relTolerance * abs(b) {
                problems.append("\(path): \(a) ≠ \(b)")
            }
        case .str(let s):
            if (theirs as? String) != s { problems.append("\(path): \"\(s)\" ≠ \(theirs)") }
        case .arr(let xs):
            guard let ys = theirs as? [Any], ys.count == xs.count else {
                problems.append("\(path): 数组长度 \(xs.count) ≠ \((theirs as? [Any])?.count ?? -1)"); return
            }
            for (k, x) in xs.enumerated() { compare(x, ys[k], path: "\(path)[\(k)]", problems: &problems) }
        case .obj(let kv):
            guard let d = theirs as? [String: Any], d.count == kv.count else {
                problems.append("\(path): 字段不一致"); return
            }
            for (k, v) in kv {
                guard let o = d[k] else { problems.append("\(path).\(k): 文件里没有"); continue }
                compare(v, o, path: "\(path).\(k)", problems: &problems)
            }
        }
    }

    // MARK: - WAV（16-bit PCM 单声道 16 kHz）

    private func writeWav(_ pcm: [Int16], name: String) throws {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(pcm.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(16_000); u32(32_000); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in pcm { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
        try d.write(to: Self.dataDir.appendingPathComponent("\(name).wav"))
    }

    private func readWav(name: String) throws -> [Int16] {
        let d = try Data(contentsOf: Self.dataDir.appendingPathComponent("\(name).wav"))
        let bytes = [UInt8](d)
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        var pos = 12
        while pos + 8 <= bytes.count {
            let id = String(decoding: bytes[pos..<(pos + 4)], as: UTF8.self)
            let size = u32(pos + 4)
            if id == "data" {
                let n = min(size, bytes.count - pos - 8) / 2
                return (0..<n).map { k in
                    let lo = UInt16(bytes[pos + 8 + 2 * k]), hi = UInt16(bytes[pos + 9 + 2 * k])
                    return Int16(bitPattern: lo | hi << 8)
                }
            }
            pos += 8 + size + (size & 1)
        }
        throw NSError(domain: "ScoringGolden", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "\(name).wav 没有 data 块"])
    }
}

// MARK: - 输入合成（只在生成模式下用；之后两端都只读 WAV）

private enum Piece {
    case silence(Double)
    /// 有声段：时长（秒）与 F0 函数（参数为段内归一化时间 0–1，返回 Hz）
    case voice(Double, (Double) -> Double)
}

/// 确定性的伪随机（xorshift32），保证每次生成的噪声一样
private struct XorShift {
    var state: UInt32
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 17; state ^= state << 5
        return Double(state) / Double(UInt32.max) * 2 - 1
    }
}

private struct ToneCase {
    let name: String
    let note: String
    let tones: [Int]
    let pieces: [Piece]

    /// 带 3 个谐波的合成元音，10 ms 淡入淡出；无声段叠加极低的确定性噪声（更像真实底噪）
    func render() -> [Int16] {
        var out: [Int16] = []
        var rng = XorShift(state: 0x9E37_79B9)
        var phase = 0.0
        for p in pieces {
            switch p {
            case .silence(let sec):
                for _ in 0..<Int(sec * 16_000) { out.append(Int16((rng.next() * 0.0008 * 32767).rounded())) }
            case .voice(let sec, let f):
                let n = Int(sec * 16_000)
                let fade = 160.0
                for k in 0..<n {
                    let hz = f(Double(k) / Double(max(n - 1, 1)))
                    phase += 2 * Double.pi * hz / 16_000
                    let env = min(1, Double(k) / fade, Double(n - 1 - k) / fade)
                    let x = env * (0.40 * sin(phase) + 0.12 * sin(2 * phase) + 0.05 * sin(3 * phase))
                        + rng.next() * 0.0008
                    out.append(Int16((x * 32767).rounded()))
                }
            }
        }
        return out
    }
}

private struct AspirationCase {
    let name: String
    let note: String
    /// (时长秒, 噪声幅度)
    let segments: [(Double, Double)]

    func render() -> [Int16] {
        var rng = XorShift(state: 0x1234_5678)
        var out: [Int16] = []
        for (sec, amp) in segments {
            for _ in 0..<Int(sec * 16_000) { out.append(Int16((rng.next() * amp * 32767).rounded())) }
        }
        return out
    }
}

extension ScoringGoldenTests {

    /// 两音节：每音节 sec 秒，中间 gap 秒无声
    private static func two(_ a: @escaping (Double) -> Double, _ b: @escaping (Double) -> Double,
                            sec: Double = 0.32, gap: Double = 0.06) -> [Piece] {
        [.silence(0.15), .voice(sec, a), .silence(gap), .voice(sec, b), .silence(0.15)]
    }

    private static let rising: (Double) -> Double = { t in t < 0.3 ? 175 - 15 * t / 0.3 : 160 + 85 * pow((t - 0.3) / 0.7, 1.4) }
    private static let falling: (Double) -> Double = { t in 290 - 145 * pow(t, 0.55) }

    fileprivate static let toneCases: [ToneCase] = [
        ToneCase(name: "t1t1_level_jitter", note: "一声读平，带 6 Hz 颤动的 ±1.5 Hz 微小抖动：验证归一化下限（应通关）",
                 tones: [1, 1],
                 pieces: [.silence(0.15), .voice(0.7, { t in 266 - 4 * t + 1.5 * sin(2 * .pi * 6 * 0.7 * t) }), .silence(0.15)]),
        ToneCase(name: "t1t1_male_level", note: "一声读平，男声低音域 ~120 Hz：下限按均值比例，与音域无关",
                 tones: [1, 1],
                 pieces: [.silence(0.15), .voice(0.7, { t in 121 - 2 * t + 0.8 * sin(2 * .pi * 5 * 0.7 * t) }), .silence(0.15)]),
        ToneCase(name: "t1t1_falling", note: "一声读成一路下滑（270→200 Hz，约 -5 半音）：走向闸门应拦下",
                 tones: [1, 1],
                 pieces: [.silence(0.15), .voice(0.7, { t in 270 - 70 * t }), .silence(0.15)]),
        ToneCase(name: "t1t1_tts_declining", note: "一声带温和句调下倾（280→250）与句末降：参照整形的去下倾",
                 tones: [1, 1],
                 pieces: [.silence(0.1), .voice(0.8, { t in 280 - 30 * t - (t > 0.85 ? 60 * (t - 0.85) : 0) }), .silence(0.1)]),
        ToneCase(name: "t2t2_rising", note: "二声 + 二声，先小凹再升，音节间 60 ms 无声",
                 tones: [2, 2], pieces: two(rising, rising)),
        ToneCase(name: "t4t4_falling", note: "四声 + 四声，前段急降",
                 tones: [4, 4], pieces: two(falling, falling)),
        ToneCase(name: "t4t4_read_flat", note: "四声词读成平调 220 Hz：应不通关",
                 tones: [4, 4], pieces: [.silence(0.15), .voice(0.7, { _ in 220 }), .silence(0.15)]),
        ToneCase(name: "t3_dipping", note: "三声曲折 180→100→220",
                 tones: [3],
                 pieces: [.silence(0.15),
                          .voice(0.5, { t in t < 0.55 ? 180 - 80 * pow(t / 0.55, 1.3) : 100 + 120 * pow((t - 0.55) / 0.45, 1.6) }),
                          .silence(0.15)]),
        ToneCase(name: "t2t4_gap", note: "二声 + 四声，中间 120 ms 无声、前后 200 ms 静音",
                 tones: [2, 4],
                 pieces: [.silence(0.2), .voice(0.3, rising), .silence(0.12), .voice(0.3, falling), .silence(0.2)]),
        ToneCase(name: "t2t2_contradict", note: "目标二声 + 二声但整段下降：参照整形应判矛盾、f0Track 返回空",
                 tones: [2, 2], pieces: two({ t in 260 - 40 * t }, { t in 220 - 60 * t })),
        // v8 走势幅度闸门的用例
        ToneCase(name: "t4t4_flat_declining", note: "四声词读平带 1.5 半音自然下倾（220→201.6 Hz）：DTW 在线内，幅度闸门应拦下",
                 tones: [4, 4], pieces: [.silence(0.15), .voice(0.7, { t in 220 * pow(2, -1.5 * t / 12) }), .silence(0.15)]),
        ToneCase(name: "t2t4_read_flat", note: "二声 + 四声读平 200 Hz，两字间 60 ms 无声：幅度闸门应拦下",
                 tones: [2, 4], pieces: two({ _ in 200 }, { _ in 199 })),
        ToneCase(name: "t3t2_compressed", note: "三声 + 二声走势压缩到约 3–4 半音（205→180→225 Hz）：读得不到位但有起伏，幅度闸门应放行",
                 tones: [3, 2], pieces: two({ t in 205 - 25 * t }, { t in 180 + 45 * pow(t, 1.4) })),
        ToneCase(name: "t1t5_read_flat", note: "一声 + 轻声读平 250 Hz：两道闸门都不适用，只看 DTW",
                 tones: [1, 5], pieces: two({ _ in 250 }, { _ in 249 })),
        ToneCase(name: "t2t4_one_syllable", note: "二声 + 四声只录到一个字（180→196 Hz，约 1.5 半音）：跨度不足会被幅度闸门拦下——已知风险边界，记录在案",
                 tones: [2, 4], pieces: [.silence(0.15), .voice(0.3, { t in 180 + 16 * t }), .silence(0.15)]),
        ToneCase(name: "short_blip", note: "只有约 30 ms 有声：有声帧不足，技术性重录",
                 tones: [1], pieces: [.silence(0.3), .voice(0.03, { _ in 200 }), .silence(0.3)]),
        ToneCase(name: "silence_only", note: "只有底噪：技术性重录",
                 tones: [1, 1], pieces: [.silence(0.8)]),
    ]

    fileprivate static let aspirationCases: [AspirationCase] = [
        AspirationCase(name: "asp_burst", note: "底噪 0.003 → 0.8 s 强气流 0.08（约 +28 dB）：应通关",
                       segments: [(0.5, 0.003), (0.3, 0.003), (0.8, 0.08), (0.4, 0.003)]),
        AspirationCase(name: "asp_weak", note: "底噪 0.003 → 气流 0.008（约 +8.5 dB，低于 +15 dB）：不应触发",
                       segments: [(0.5, 0.003), (0.3, 0.003), (0.8, 0.008), (0.4, 0.003)]),
        AspirationCase(name: "asp_short_burst", note: "强气流只持续 0.3 s：600 ms 窗口触发率到不了 0.6",
                       segments: [(0.5, 0.003), (0.3, 0.003), (0.3, 0.08), (0.6, 0.003)]),
    ]
}

// MARK: - 极简 JSON（Float 用 Swift 的最短往返表示，两端解析都无歧义）

private indirect enum J {
    case null, bool(Bool), int(Int), float(Float), str(String), arr([J]), obj([(String, J)])

    static func floats(_ xs: [Float]) -> J { .arr(xs.map(J.float)) }
    static func ints(_ xs: [Int]) -> J { .arr(xs.map(J.int)) }

    func render(indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let v): return String(v)
        case .float(let f):
            precondition(f.isFinite, "对照数据里不应出现非有限值")
            return "\(f)"
        case .str(let s):
            var out = "\""
            for ch in s.unicodeScalars {
                switch ch {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                case "\n": out += "\\n"
                default: out.unicodeScalars.append(ch)
                }
            }
            return out + "\""
        case .arr(let xs):
            // 标量数组一行写完，文件好读、diff 好看
            if xs.allSatisfy({ if case .arr = $0 { return false }; if case .obj = $0 { return false }; return true }) {
                return "[" + xs.map { $0.render(indent: 0) }.joined(separator: ", ") + "]"
            }
            return "[\n" + xs.map { pad + "  " + $0.render(indent: indent + 1) }.joined(separator: ",\n")
                + "\n" + pad + "]"
        case .obj(let kv):
            return "{\n" + kv.map { pad + "  " + J.str($0.0).render(indent: 0) + ": " + $0.1.render(indent: indent + 1) }
                .joined(separator: ",\n") + "\n" + pad + "}"
        }
    }
}
