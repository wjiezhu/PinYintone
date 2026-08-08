import AVFoundation
import Combine
import Foundation

/// 声调训练核心业务逻辑：串联 AudioEngine → AudioFramer → F0Extractor → DTWAnalyzer，
/// 并保存训练记录。
///
/// 实验完整性要点（仅作用于关卡 2）：
/// - **参照锁定**：录音开始时把当前参照曲线拷入 `lockedReference`，本次录音的
///   显示与评分都用它；异步参照（真人音 / TTS）若在录音中返回则暂存，录完再应用。
///   保证"所见即所评"——这是动态曲线反馈成立的最低要求。
/// - **参照优先级**：真人母语者录音 > TTS 合成 > 几何理想轮廓，来源随记录上报。
/// - **技术性失败不计分**：有声帧过少视为"没录好"，提示重录且不生成/不持久化记录，
///   避免与"发音错"混为一谈污染统计。
/// - **按词累计尝试数**：`attemptNumber` 不再每次换词归零，可还原练习轮次。
@MainActor
final class ToneTrainingViewModel: ObservableObject {
    @Published var currentLexeme: Lexeme?
    @Published var studentF0: [Float] = []      // 学习者实时 F0（已归一化）
    @Published var referenceF0: [Float] = []    // 母语者参照 F0（已归一化）
    @Published var feedbackResult: FeedbackResult?
    @Published var isRecording: Bool = false
    /// 当前实验阶段。前测/后测为裸测（不显示反馈），仅训练期显示反馈。
    /// 由上层（前测引导 / 后测入口）设置；默认训练期。
    @Published var phase: TrainingPhase = .training
    /// 参照曲线是否已定稿。未就绪时视图层禁用录音按钮（堵住竞态窗口）
    @Published var isReferenceReady: Bool = false
    /// 技术性失败提示（如"没听清，请靠近麦克风重录"）；非发音评价
    @Published var retryHint: String?
    /// 当前词连续未通关次数，达到阈值后视图层提示"可以先跳过"
    @Published var consecutiveFailures: Int = 0

    private let audioEngine = AudioEngine()
    private let framer = AudioFramer()           // 512/128 帧化（CLAUDE.md）
    private let f0Extractor = F0Extractor()
    private let dtwAnalyzer = DTWAnalyzer()

    private var accumulatedF0: [Float] = []      // 原始 Hz 序列（含 0 无声帧）

    // MARK: - 参照曲线状态

    /// 本次录音锁定的参照（显示 + 评分同源）
    private var lockedReference: [Float] = []
    private var lockedReferenceType: ReferenceType = .ideal
    /// 当前参照来源
    private var referenceType: ReferenceType = .ideal
    /// 录音中到达的异步参照，录完后再应用（保证一次录音全程参照线不变）
    private var pendingReference: ([Float], ReferenceType)?

    // MARK: - 尝试计数与埋点

    /// 每词累计尝试数，持久化；换词不归零（P1-3）
    private var attemptsByLexeme: [String: Int] = [:]
    private static let attemptsKey = "pt_tone_attempts"

    /// 有声帧下限：低于此值判为"没录好"，不计分（≈40 ms 有效发声）
    private let minVoicedFrames = 5
    /// 异常高分阈值：超出即打 qualityFlag，分析时可剔除
    private let qualityFlagThreshold: Float = 2.0
    /// 同词连续失败达此次数即提示可跳过
    let skipHintThreshold = 3

    /// 实时曲线刷新节流时间戳。帧移 128 samples ≈ 每 8ms 一帧，
    /// 若每帧都对整条累积序列做全量 normalize + 触发 Canvas 重绘（模式 B），
    /// 主线程会被打爆 → watchdog 终止进程。节流到 ~12fps 既流畅又不崩。
    private var lastCurveRefresh: Date = .distantPast
    private let curveRefreshInterval: TimeInterval = 0.08   // ≈12fps

    /// 视图层应绘制的参照：录音中用锁定值，其余用当前值
    var displayReference: [Float] { isRecording ? lockedReference : referenceF0 }

    init() {
        attemptsByLexeme = (UserDefaults.standard.dictionary(forKey: Self.attemptsKey)
                            as? [String: Int]) ?? [:]
        // 帧化层每凑满帧 → 提 F0 → 累积；实时曲线节流刷新（见 lastCurveRefresh）
        framer.onFrame = { [weak self] frame in
            guard let self else { return }
            let hz = self.f0Extractor.extract(frame: frame)
            Task { @MainActor in
                self.accumulatedF0.append(hz)
                // 节流：高频全量 normalize + Canvas 重绘会拖垮主线程（模式 B 闪退根因）
                if Date().timeIntervalSince(self.lastCurveRefresh) >= self.curveRefreshInterval {
                    self.lastCurveRefresh = Date()
                    // clean：八度纠错 + 去尖峰，避免曲线出现 2× 跳变毛刺
                    self.studentF0 = self.f0Extractor.normalize(
                        self.f0Extractor.clean(self.accumulatedF0))
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
        // 即时占位：几何理想轮廓；随后异步升级为真人录音 / TTS 参照
        referenceF0 = f0Extractor.normalize(Self.idealContour(for: lexeme.tones))
        referenceType = .ideal
        isReferenceReady = false
        pendingReference = nil
        studentF0 = []
        accumulatedF0 = []
        feedbackResult = nil
        retryHint = nil
        consecutiveFailures = 0

        let targetID = lexeme.id
        Task { [weak self] in
            guard let self else { return }
            // 优先级：真人母语者录音 → TTS 合成 → 保持几何理想轮廓
            var track: [Float] = []
            var type: ReferenceType = .ideal
            if let file = lexeme.audioFilename, !file.isEmpty {
                track = await SpeechService.shared.referenceF0FromBundledAudio(named: file)
                if !track.isEmpty { type = .real }
            }
            if track.isEmpty {
                // 传入目标声调：用于消除 TTS 句调下倾并校验可信度
                track = await SpeechService.shared.synthesizeReferenceF0(
                    for: lexeme.hanzi, tones: lexeme.tones)
                if !track.isEmpty { type = .tts }
            }
            await MainActor.run {
                guard self.currentLexeme?.id == targetID else { return }
                self.applyReference(track: track, type: type)
            }
        }
    }

    /// 应用异步参照。录音进行中则暂存，录完再应用——保证一次录音全程参照线不变。
    private func applyReference(track: [Float], type: ReferenceType) {
        guard !track.isEmpty else {
            // 真人音与 TTS 都失败：保持几何理想轮廓，直接定稿
            isReferenceReady = true
            return
        }
        if isRecording {
            pendingReference = (track, type)
            return
        }
        referenceF0 = track
        referenceType = type
        isReferenceReady = true
    }

    /// 朗读样例读音
    func playSample() {
        guard let hanzi = currentLexeme?.hanzi else { return }
        SpeechService.shared.speak(hanzi)
    }

    func loadNext() {
        loadLexeme(CorpusLoader.shared.nextLexeme(category: .tone))
    }

    /// 当前词表进度（1-based / 总数），供视图显示
    var progress: (index: Int, total: Int) {
        CorpusLoader.shared.progress(category: .tone)
    }

    // MARK: - 录音

    func startRecording() {
        accumulatedF0 = []
        studentF0 = []
        feedbackResult = nil
        retryHint = nil
        lastCurveRefresh = .distantPast   // 让本次录音第一帧立即刷新曲线
        framer.reset()
        // 锁定参照：本次录音的显示与评分都用它
        lockedReference = referenceF0
        lockedReferenceType = referenceType
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

        let cleaned = f0Extractor.clean(accumulatedF0)
        let voicedFrames = cleaned.filter { $0 != 0 }.count

        // P1-2：技术性失败（没录好）与发音错误分开，不生成结果、不入库
        guard voicedFrames >= minVoicedFrames else {
            studentF0 = []
            retryHint = NSLocalizedString("tone_retry_no_voice", comment: "")
            flushPendingReference()
            return
        }

        let normalized = f0Extractor.normalize(cleaned)
        studentF0 = normalized

        // 评分用锁定参照，与录音期间显示的是同一条线
        let reference = lockedReference.isEmpty ? referenceF0 : lockedReference
        let score = dtwAnalyzer.distance(reference: reference, candidate: normalized)
        let grade = dtwAnalyzer.grade(dtwScore: score)

        // 按词累计尝试数（换词不归零）
        let lexemeID = currentLexeme?.id ?? "unknown"
        let attempt = (attemptsByLexeme[lexemeID] ?? 0) + 1
        attemptsByLexeme[lexemeID] = attempt
        UserDefaults.standard.set(attemptsByLexeme, forKey: Self.attemptsKey)

        consecutiveFailures = (grade == .fail) ? consecutiveFailures + 1 : 0

        let segments = buildSegments(student: normalized, reference: reference)
        let result = FeedbackResult(
            dtwScore: score,
            grade: grade,
            attemptNumber: attempt,
            segments: segments
        )
        feedbackResult = result

        // 参照在本次录音中是否被换过——P0-3 修复后应恒为 false（不变式自检）
        let switched = !lockedReference.isEmpty && lockedReference != referenceF0
        persist(result,
                referenceType: lockedReferenceType,
                voicedFrameCount: voicedFrames,
                qualityFlag: score >= qualityFlagThreshold,
                referenceSwitched: switched)

        flushPendingReference()
    }

    /// 录音结束后应用暂存的异步参照
    private func flushPendingReference() {
        if let (track, type) = pendingReference {
            referenceF0 = track
            referenceType = type
            pendingReference = nil
        }
        isReferenceReady = true
    }

    // MARK: - 按字诊断

    /// 计算每个音节的分段 DTW + 方向提示。两组（A/B）都在录完后看。
    private func buildSegments(student: [Float], reference: [Float]) -> [ToneSegmentResult] {
        guard let lexeme = currentLexeme, !lexeme.tones.isEmpty else { return [] }
        let n = lexeme.tones.count
        let segScores = dtwAnalyzer.segmentScores(
            reference: reference, candidate: student, nSegments: n
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

    private func persist(_ result: FeedbackResult,
                         referenceType: ReferenceType,
                         voicedFrameCount: Int,
                         qualityFlag: Bool,
                         referenceSwitched: Bool) {
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
            timestamp: Date(),
            referenceType: referenceType.rawValue,
            voicedFrameCount: voicedFrameCount,
            qualityFlag: qualityFlag,
            referenceSwitchedDuringAttempt: referenceSwitched,
            phase: phase.rawValue,
            appVersion: AppInfo.versionString
        )
    }

    // MARK: - 理想四声轮廓合成

    /// 按声调序列生成理想 F0 轮廓（Hz 量级）；归一化后作母语者参照。
    static func idealContour(for tones: [Int]) -> [Float] {
        ToneContour.ideal(for: tones)
    }
}
