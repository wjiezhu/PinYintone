import AVFoundation
import Combine
import Foundation

/// 声调训练核心业务逻辑：串联 AudioEngine → AudioFramer → F0Extractor → DTWAnalyzer，
/// 并保存训练记录。
///
/// 实验完整性要点（仅作用于关卡 2）：
/// - **三阶段**：`pretest` / `posttest` 为裸测——照常算分入库，但**不向学习者呈现**
///   任何分数、等级、颜色或曲线，录完自动进下一题；`training` 才显示反馈。
/// - **反馈呈现**：训练阶段一律动态 F0 可视化（已取消 A/B 分组）。
@MainActor
final class ToneTrainingViewModel: ObservableObject {
    @Published var currentLexeme: Lexeme?
    /// 当前研究阶段；测试阶段不呈现任何反馈（升级需求 §3.1）
    @Published private(set) var phase: TrainingPhase = .pretest
    /// 当前词条的反馈条件；测试阶段与无词集词条为 nil（升级需求 §3.2）
    /// 测试阶段词表是否已走完
    @Published private(set) var isPhaseComplete: Bool = false
    @Published var studentF0: [Float] = []      // 学习者实时 F0（已归一化）
    @Published var referenceF0: [Float] = []    // 母语者参照 F0（已归一化）
    @Published var feedbackResult: FeedbackResult?
    @Published var isRecording: Bool = false
    /// 参照曲线是否已定稿。未就绪时视图层禁用录音按钮（堵住竞态窗口）
    @Published var isReferenceReady: Bool = false
    /// 技术性失败提示（如"没听清，请靠近麦克风重录"）；非发音评价
    @Published var retryHint: String?
    /// 当前词连续未通关次数，达到阈值后视图层提示"可以先跳过"
    @Published var consecutiveFailures: Int = 0
    /// 测试阶段的中性提示（"已记录"）。不含任何评价信息，仅告知录音被保存。
    @Published private(set) var assessmentNotice: String?

    private let sequencer: ToneSequencer
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

    /// 注意：默认参数会在**调用方**的隔离域里求值（`@StateObject` 的 autoclosure
    /// 是非隔离的），所以不能写成 `sequencer: ToneSequencer = .shared`。
    /// 传 nil 时在 init 体内取单例——init 本身是 @MainActor，隔离正确。
    init(sequencer: ToneSequencer? = nil) {
        let sequencer = sequencer ?? ToneSequencer.shared
        self.sequencer = sequencer
        phase = sequencer.phase
        isPhaseComplete = sequencer.isPhaseComplete
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
        assessmentNotice = nil
        consecutiveFailures = 0
        // 条件绑定词集：换词就可能换条件（受试内设计）

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

    /// 载入当前阶段的当前题（进入页面 / 阶段切换后调用）
    func loadCurrent() {
        syncPhaseState()
        guard let lexeme = sequencer.currentLexeme else {
            currentLexeme = nil
            return
        }
        loadLexeme(lexeme)
    }

    /// 进入下一题。测试阶段走完最后一题后 `currentLexeme` 为 nil，视图显示阶段完成。
    func loadNext() {
        sequencer.advance()
        loadCurrent()
    }

    /// 训练阶段解锁后，主动开始后测
    func beginPosttest() {
        sequencer.beginPosttest()
        loadCurrent()
    }

    var isPosttestUnlocked: Bool { sequencer.isPosttestUnlocked }

    /// 当前阶段词表进度（1-based / 总数），供视图显示
    var progress: (index: Int, total: Int) { sequencer.progress }

    /// 把排程状态同步到 @Published，供视图分支
    private func syncPhaseState() {
        phase = sequencer.phase
        isPhaseComplete = sequencer.isPhaseComplete
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
        // start 失败（无输入设备 / 权限被拒 / 会话被占用 / 路由切换）时回滚，
        // 并且**必须给出可执行提示**：否则学习者看到的是一个按了没反应的按钮
        // （档案 §4.2、§11 都要求这条路径有明确恢复路径）。
        do {
            try audioEngine.start()
        } catch {
            isRecording = false
            retryHint = NSLocalizedString("tone_retry_mic_unavailable", comment: "")
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
        let attempt = ToneAttemptStore.increment(lexemeID)

        let segments = buildSegments(student: normalized, reference: reference)
        let result = FeedbackResult(
            dtwScore: score,
            grade: grade,
            attemptNumber: attempt,
            segments: segments
        )

        // 参照在本次录音中是否被换过——P0-3 修复后应恒为 false（不变式自检）
        let switched = !lockedReference.isEmpty && lockedReference != referenceF0
        persist(result,
                referenceType: lockedReferenceType,
                voicedFrameCount: voicedFrames,
                qualityFlag: score >= qualityFlagThreshold,
                referenceSwitched: switched)

        flushPendingReference()

        // 裸测阶段：算分照常入库，但**不向学习者呈现**分数/等级/曲线，
        // 也不累计"连续失败"（那是训练阶段的行动提示逻辑）；录完自动进下一题。
        guard phase.showsFeedback else {
            studentF0 = []
            assessmentNotice = NSLocalizedString("assessment_recorded", comment: "")
            scheduleAssessmentAdvance()
            return
        }

        consecutiveFailures = (grade == .fail) ? consecutiveFailures + 1 : 0
        feedbackResult = result
    }

    /// 测试阶段自动进入下一题。留出一拍让"已记录"提示可见，避免像是没录上。
    private func scheduleAssessmentAdvance() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !self.isRecording, self.phase.isAssessment else { return }
            self.loadNext()
        }
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
        // 已取消 A/B 分组。feedbackMode 记的是"这条记录当时用的哪种显示模式"，
        // 由学习者自己在设置里选，**不是实验条件**——自选数据不得做组间比较。
        // 裸测阶段不显示任何反馈，故为 nil。
        // groupAssignment 是历史必填列，恒写 "n/a" 表示不参与任何分组。
        let shownStyle = sequencer.phase.showsFeedback ? FeedbackStyle.current.rawValue : nil
        SessionRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            groupAssignment: "n/a",
            lexemeID: lexeme.id,
            dtwScore: Double(result.dtwScore),
            grade: result.grade.rawValue,
            attemptNumber: result.attemptNumber,
            timestamp: Date(),
            referenceType: referenceType.rawValue,
            voicedFrameCount: voicedFrameCount,
            qualityFlag: qualityFlag,
            referenceSwitchedDuringAttempt: referenceSwitched,
            phase: sequencer.phase.rawValue,
            wordSetID: lexeme.wordSet?.rawValue,
            assessmentSetVersion: lexeme.wordSet?.isAssessment == true
                ? AssessmentSet.version : nil,
            feedbackMode: shownStyle,
            // 走到这里说明 F0 分析已成功产出评分；质量异常仍保留记录但显式标记，
            // 供导出时剔除（升级需求 §6.1）。技术失败根本不会走到 persist——
            // 那条路径只提示重录、不生成记录。
            resultStatus: qualityFlag ? .qualityFlagged : .validResult
        )
    }

    // MARK: - 理想四声轮廓合成

    /// 按声调序列生成理想 F0 轮廓（Hz 量级）；归一化后作母语者参照。
    static func idealContour(for tones: [Int]) -> [Float] {
        ToneContour.ideal(for: tones)
    }
}
