import AVFoundation
import Combine
import Foundation

/// 声调训练核心业务逻辑：串联 AudioEngine → AudioFramer → F0Extractor → DTWAnalyzer，
/// 并保存训练记录。母语者参照 F0 暂用「按 tones 合成的理想四声轮廓」（后续可替换为真实录音）。
@MainActor
final class ToneTrainingViewModel: ObservableObject {
    @Published var currentLexeme: Lexeme?
    @Published var studentF0: [Float] = []      // 学习者实时 F0（已归一化）
    @Published var referenceF0: [Float] = []    // 母语者参照 F0（已归一化）
    @Published var feedbackResult: FeedbackResult?
    @Published var isRecording: Bool = false

    private let audioEngine = AudioEngine()
    private let framer = AudioFramer()           // 512/128 帧化（CLAUDE.md）
    private let f0Extractor = F0Extractor()
    private let dtwAnalyzer = DTWAnalyzer()

    private var accumulatedF0: [Float] = []      // 原始 Hz 序列（含 0 无声帧）
    private var attemptCount = 0
    /// 实时曲线刷新节流时间戳。帧移 128 samples ≈ 每 8ms 一帧，
    /// 若每帧都对整条累积序列做全量 normalize + 触发 Canvas 重绘（模式 B），
    /// 主线程会被打爆 → watchdog 终止进程。节流到 ~12fps 既流畅又不崩。
    private var lastCurveRefresh: Date = .distantPast
    private let curveRefreshInterval: TimeInterval = 0.08   // ≈12fps

    init() {
        // 帧化层每凑满帧 → 提 F0 → 累积；实时曲线节流刷新（见 lastCurveRefresh）
        framer.onFrame = { [weak self] frame in
            guard let self else { return }
            let hz = self.f0Extractor.extract(frame: frame)
            Task { @MainActor in
                self.accumulatedF0.append(hz)
                // 节流：高频全量 normalize + Canvas 重绘会拖垮主线程（模式 B 闪退根因）
                if Date().timeIntervalSince(self.lastCurveRefresh) >= self.curveRefreshInterval {
                    self.lastCurveRefresh = Date()
                    self.studentF0 = self.f0Extractor.normalize(self.accumulatedF0)
                }
            }
        }
        audioEngine.onChunk = { [weak self] pcm in
            self?.framer.feed(pcm)
        }
    }

    // MARK: - 词条

    func loadLexeme(_ lexeme: Lexeme) {
        currentLexeme = lexeme
        // 即时占位：几何理想轮廓；随后异步升级为 TTS 合成的母语者参照
        referenceF0 = f0Extractor.normalize(Self.idealContour(for: lexeme.tones))
        studentF0 = []
        accumulatedF0 = []
        feedbackResult = nil
        attemptCount = 0

        let targetID = lexeme.id
        Task { [weak self] in
            let tts = await SpeechService.shared.synthesizeReferenceF0(for: lexeme.hanzi)
            await MainActor.run {
                guard let self, self.currentLexeme?.id == targetID, !tts.isEmpty else { return }
                self.referenceF0 = tts
            }
        }
    }

    /// 朗读样例读音
    func playSample() {
        guard let hanzi = currentLexeme?.hanzi else { return }
        SpeechService.shared.speak(hanzi)
    }

    func loadNext() {
        loadLexeme(CorpusLoader.shared.nextLexeme(category: .tone))
    }

    // MARK: - 录音

    func startRecording() {
        accumulatedF0 = []
        studentF0 = []
        feedbackResult = nil
        lastCurveRefresh = .distantPast   // 让本次录音第一帧立即刷新曲线
        framer.reset()
        isRecording = true
        // start 失败（无麦克风 / 权限被拒）时回滚，避免 UI 卡在"录音中"
        do {
            try audioEngine.start()
        } catch {
            isRecording = false
        }
    }

    func stopRecordingAndEvaluate() {
        audioEngine.stop()
        isRecording = false
        attemptCount += 1

        let normalized = f0Extractor.normalize(accumulatedF0)
        studentF0 = normalized
        let score = dtwAnalyzer.distance(reference: referenceF0, candidate: normalized)
        let grade = dtwAnalyzer.grade(dtwScore: score)

        let segments = buildSegments(student: normalized)
        let result = FeedbackResult(
            dtwScore: score,
            grade: grade,
            attemptNumber: attemptCount,
            segments: segments
        )
        feedbackResult = result
        persist(result)
    }

    // MARK: - 按字诊断

    /// 计算每个音节的分段 DTW + 方向提示。两组（A/B）都在录完后看。
    private func buildSegments(student: [Float]) -> [ToneSegmentResult] {
        guard let lexeme = currentLexeme, !lexeme.tones.isEmpty else { return [] }
        let n = lexeme.tones.count
        let segScores = dtwAnalyzer.segmentScores(
            reference: referenceF0, candidate: student, nSegments: n
        )

        // 学生 F0 同步等分（去 0 后），用于方向分析
        let voiced = student.filter { $0 != 0 }
        let chars = Array(lexeme.hanzi)

        var out: [ToneSegmentResult] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let tone = lexeme.tones[i]
            let segStart = (voiced.count * i) / n
            let segEnd   = (voiced.count * (i + 1)) / n
            let studentSeg = (segStart < segEnd) ? Array(voiced[segStart..<segEnd]) : []
            let hint = directionHint(for: tone, studentSegment: studentSeg,
                                     overallPassed: segScores[i] <= 0.5)
            let ch = i < chars.count ? String(chars[i]) : "?"
            out.append(ToneSegmentResult(
                syllableIndex: i,
                hanziChar: ch,
                expectedTone: tone,
                segmentScore: segScores[i],
                directionHint: hint
            ))
        }
        return out
    }

    /// 通过学生段的三等分（起/中/末）均值，识别走向并对照目标声调，输出方向提示。
    /// 若分段评分已通关（≤ 0.5），返回 `.ok`，不画箭头。
    private func directionHint(for tone: Int,
                               studentSegment voiced: [Float],
                               overallPassed: Bool) -> DirectionHint {
        if overallPassed { return .ok }
        guard voiced.count >= 3 else { return .neutral }

        let third = max(1, voiced.count / 3)
        let start = voiced.prefix(third)
        let mid   = voiced.dropFirst(third).prefix(third)
        let end   = voiced.suffix(third)
        let avg: ([Float]) -> Float = { s in
            guard !s.isEmpty else { return 0 }
            return s.reduce(0, +) / Float(s.count)
        }
        let aStart = avg(Array(start))
        let aMid   = avg(Array(mid))
        let aEnd   = avg(Array(end))

        // z-score 单位下，0.5 是一个明显的走向阈值
        let SLOPE: Float = 0.5
        let DIP: Float   = 0.3

        switch tone {
        case 1: return .shouldStayHigh                                   // 没保持平
        case 2: return aEnd > aStart + SLOPE ? .ok : .shouldRise         // 没升上去
        case 3: return (min(aStart, aEnd) - aMid) > DIP ? .ok            // 中段确实更低
                       : .shouldDipThenRise
        case 4: return aEnd < aStart - SLOPE ? .ok : .shouldFall         // 没降下来
        case 5: return .neutral                                          // 轻声不指点
        default: return .neutral
        }
    }

    // MARK: - 持久化

    private func persist(_ result: FeedbackResult) {
        guard let profile = UserManager.shared.profile,
              let lexeme = currentLexeme else { return }
        SessionRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            groupAssignment: profile.experimentGroup,
            lexemeID: lexeme.id,
            dtwScore: Double(result.dtwScore),
            grade: result.grade.rawValue,
            attemptNumber: result.attemptNumber,
            timestamp: Date()
        )
    }

    // MARK: - 理想四声轮廓合成

    /// 按声调序列生成理想 F0 轮廓（Hz 量级）；归一化后作母语者参照。
    static func idealContour(for tones: [Int]) -> [Float] {
        ToneContour.ideal(for: tones)
    }
}
