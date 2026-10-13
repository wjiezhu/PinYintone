import AVFoundation
import Combine
import Foundation
import UIKit

/// 声调练习的核心业务逻辑：录音 → 帧化 → F0 → DTW，并保存记录。
///
/// 两种用法（需求 R06）：
/// - **普通练习**（默认）：有反馈，可选词、换词、重复录音，随时退出。没有任何前置门槛。
/// - **自测**（学习者从次级菜单主动开始）：只推进录音，不呈现分数、等级、颜色、
///   参考曲线、示范或建议；可随时取消，取消与完成都回到普通练习。
///
/// 评分管线两种用法完全相同，本类型**不改动**任何评分参数（CLAUDE.md）。
@MainActor
final class ToneTrainingViewModel: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    // MARK: - 状态机

    /// 录音流程的可见状态（需求 U03）。界面只按它决定显示什么、哪些按钮可用，
    /// 不再从一堆布尔值里各自推断。
    enum Stage: Equatable {
        /// 正在准备参考曲线。此时不能开始录音。
        case preparing
        /// 可以录音
        case ready
        case recording
        case analyzing
        /// 有效结果已出（普通练习）
        case feedback
        /// 自测：这一词已录到，稍后自动进入下一词
        case selfTestRecorded
        /// 技术原因没成，可恢复。**不是低分**，也没有成绩。
        case failed(Failure)
    }

    /// 技术失败的种类。每一种都对应一句说明**下一步怎么做**的话。
    enum Failure: Equatable {
        /// 麦克风权限未开。提供去系统设置的入口；回来后重新检查。
        case microphoneDenied
        /// 录音没能启动（无输入设备、会话被占用等）
        case microphoneUnavailable
        /// 没录到声音
        case noVoice
        /// 录音被打断（来电、切到后台等）
        case interrupted
        /// 分析没得出有效结果
        case analysis
        /// 回听或示范播放失败
        case playback

        var messageKey: String {
            switch self {
            case .microphoneDenied:      return "tone_fail_mic_denied"
            case .microphoneUnavailable: return "tone_retry_mic_unavailable"
            case .noVoice:               return "tone_retry_no_voice"
            case .interrupted:           return "tone_fail_interrupted"
            case .analysis:              return "tone_fail_analysis"
            case .playback:              return "replay_failed"
            }
        }

        var offersSettings: Bool { self == .microphoneDenied }
    }

    enum Mode: Equatable { case practice, selfTest }

    @Published private(set) var stage: Stage = .preparing
    @Published private(set) var mode: Mode = .practice
    @Published private(set) var currentLexeme: Lexeme?
    @Published private(set) var studentF0: [Float] = []      // 学习者实时 F0（已归一化）
    @Published private(set) var referenceF0: [Float] = []    // 参照 F0（已归一化）
    @Published private(set) var feedbackResult: FeedbackResult?
    /// 示范或回听是否正在播放（驱动按钮图标；二者互斥）
    @Published private(set) var playing: Playback?
    /// 当前词连续未通过次数，达到阈值后提示「可以先换一个词」
    @Published private(set) var consecutiveFailures: Int = 0
    /// 自测进度；不在自测时为 nil
    @Published private(set) var selfTest: SelfTestSession?
    /// 自测刚刚走完（界面显示完成页）
    @Published private(set) var selfTestFinished = false
    /// 建议面板是否展开。**只由用户点击触发**，任何代码路径都不得自动置 true。
    @Published var showAdvice = false
    /// 有一份使用后问卷的邀请该展示了。只在用户结束当前反馈之后才置位。
    @Published var postSurveyInvitation: SurveyRecord?

    enum Playback: Equatable { case sample, ownRecording }

    var isRecording: Bool { stage == .recording }
    /// 录音、分析期间不能切词、切模式或播放（需求 U03）
    var isBusy: Bool { stage == .recording || stage == .analyzing }
    var canRecord: Bool {
        switch stage {
        case .ready, .feedback, .failed, .recording: return true
        case .preparing, .analyzing, .selfTestRecorded: return false
        }
    }
    var failure: Failure? {
        if case .failed(let f) = stage { return f }
        return nil
    }
    /// 是否有可回听的录音
    var canReplay: Bool { LearnerRecordingStore.shared.hasRecording && mode == .practice }
    /// 视图层应绘制的参照：录音中用锁定值，其余用当前值
    var displayReference: [Float] { isRecording ? lockedReference : referenceF0 }
    /// 词表进度（普通练习）
    var progress: (index: Int, total: Int) { sequencer.progress }
    /// 同词连续未通过达此次数即提示可以换词
    let skipHintThreshold = 3

    private(set) var currentAdvice: PracticeAdvice = .make(result: nil, lexemeID: nil)

    // MARK: - 依赖

    private let sequencer: ToneSequencer
    private let recorder: RecordingSource
    /// 录音来源是否为真实麦克风。不是的话（界面测试的合成信号、单元测试的替身）
    /// 不申请麦克风权限，也不做 TTS 参照合成——两者在无人值守的环境里都不可靠。
    private let usesMicrophone: Bool
    private let framer = AudioFramer()           // 512/128 帧化（CLAUDE.md）
    private let f0Extractor = F0Extractor()
    private let dtwAnalyzer = DTWAnalyzer()

    private var accumulatedF0: [Float] = []      // 原始 Hz 序列（含 0 无声帧）

    // MARK: - 参照曲线状态

    /// 本次录音锁定的参照（显示 + 评分同源）
    private var lockedReference: [Float] = []
    private var lockedReferenceType: ReferenceType = .ideal
    private var referenceType: ReferenceType = .ideal
    /// 录音中到达的异步参照，录完后再应用（保证一次录音全程参照线不变）
    private var pendingReference: ([Float], ReferenceType)?
    private var isReferenceReady = false

    // MARK: - 尝试与埋点

    /// 有声帧下限：低于此值判为「没录好」，不计分（≈40 ms 有效发声）
    private let minVoicedFrames = 5
    /// 异常高分阈值：超出即打 qualityFlag，分析时可剔除
    private let qualityFlagThreshold: Float = 2.0

    /// 实时曲线刷新节流。帧移 128 samples ≈ 每 8ms 一帧，若每帧都对整条累积序列
    /// 做全量 normalize + 触发 Canvas 重绘，主线程会被打爆 → watchdog 终止进程。
    private var lastCurveRefresh: Date = .distantPast
    private let curveRefreshInterval: TimeInterval = 0.08   // ≈12fps

    /// 本次尝试的研究编号。录音开始时生成；**每次真实录音一个新编号**。
    private(set) var currentAttemptID: UUID?
    /// 同一个词上一次录音的编号。重录时写进新尝试的 `retry_of_attempt_id`。
    private var previousAttemptID: UUID?
    /// 已经报过「反馈已呈现」的尝试。视图重绘不重复计。
    private var displayedAttemptIDs: Set<UUID> = []
    private var cancellables: Set<AnyCancellable> = []

    /// 注意：默认参数会在**调用方**的隔离域里求值（`@StateObject` 的 autoclosure
    /// 是非隔离的），所以不能写成 `sequencer: ToneSequencer = .shared`。
    init(sequencer: ToneSequencer? = nil, recorder: RecordingSource? = nil) {
        self.sequencer = sequencer ?? ToneSequencer.shared
        let source = recorder ?? RecordingSourceFactory.make()
        self.recorder = source
        self.usesMicrophone = source is AudioEngine

        // 帧化层每凑满帧 → 提 F0 → 累积；实时曲线节流刷新
        framer.onFrame = { [weak self] frame in
            guard let self else { return }
            let hz = self.f0Extractor.extract(frame: frame)
            Task { @MainActor in
                guard self.stage == .recording else { return }
                self.accumulatedF0.append(hz)
                // 自测不画任何曲线
                guard self.mode == .practice else { return }
                if Date().timeIntervalSince(self.lastCurveRefresh) >= self.curveRefreshInterval {
                    self.lastCurveRefresh = Date()
                    // clean：八度纠错 + 去尖峰，避免曲线出现 2× 跳变毛刺
                    self.studentF0 = self.f0Extractor.normalize(
                        self.f0Extractor.clean(self.accumulatedF0))
                }
            }
        }
        // 接住整段 PCM 供回听。只存内存、只留当前一条，原始录音不上传。
        self.recorder.onFinish = { [weak self] pcm in
            guard let self, self.mode == .practice else { return }
            LearnerRecordingStore.shared.store(pcm: pcm, lexemeID: self.currentLexeme?.id)
        }
        self.recorder.onChunk = { [weak self] pcm in
            self?.framer.feed(pcm)
        }
        observeInterruptions()
    }

    // MARK: - 词条

    /// 进入练习页：载入上次停留的词
    func loadCurrent() {
        guard mode == .practice else { return }
        if let lexeme = sequencer.currentLexeme {
            loadLexeme(lexeme)
        } else {
            currentLexeme = nil
        }
    }

    /// 下一个词。录音、分析期间不可换词。
    func loadNext() {
        guard !isBusy, mode == .practice else { return }
        finishViewingFeedback()
        sequencer.advance()
        loadCurrent()
    }

    /// 从词表里选了某个词
    func select(lexemeID: String) {
        guard !isBusy, mode == .practice else { return }
        finishViewingFeedback()
        if sequencer.select(lexemeID: lexemeID) { loadCurrent() }
    }

    func loadLexeme(_ lexeme: Lexeme) {
        stopAllPlayback()
        ResearchEventLog.shared.log(
            .taskOpened,
            lexemeVersionID: ResearchLexicon.versionID(for: lexeme.id),
            payload: ["task_type": taskType.rawValue])
        // 换词即清上一条录音，否则回听会放出上一个词的声音
        LearnerRecordingStore.shared.clearIfLexemeChanged(to: lexeme.id)
        if currentLexeme?.id != lexeme.id { previousAttemptID = nil }
        currentLexeme = lexeme
        // 即时占位：几何理想轮廓；随后异步升级为真人录音 / TTS 参照
        referenceF0 = f0Extractor.normalize(Self.idealContour(for: lexeme.tones))
        referenceType = .ideal
        isReferenceReady = false
        pendingReference = nil
        studentF0 = []
        accumulatedF0 = []
        feedbackResult = nil
        consecutiveFailures = 0
        currentAttemptID = nil
        stage = .preparing

        // 不是真实麦克风时不做 TTS 参照合成：无人值守的模拟器上它慢且不稳定
        if !usesMicrophone {
            markReferenceReady()
            return
        }

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
            markReferenceReady()
            return
        }
        if isBusy {
            pendingReference = (track, type)
            return
        }
        referenceF0 = track
        referenceType = type
        markReferenceReady()
    }

    private func markReferenceReady() {
        isReferenceReady = true
        if stage == .preparing { stage = .ready }
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

    private var taskType: ResearchAttemptRecord.TaskType {
        mode == .selfTest ? .selfTest : .fixedWord
    }

    private var lexemeVersionID: String? { ResearchLexicon.versionID(for: currentLexeme?.id) }

    // MARK: - 自测

    /// 学习者从次级菜单主动开始自测
    func beginSelfTest() {
        guard !isBusy else { return }
        finishViewingFeedback()
        stopAllPlayback()
        let words = CorpusLoader.shared.assessmentPool().map(\.id)
        guard !words.isEmpty else { return }
        mode = .selfTest
        selfTestFinished = false
        selfTest = SelfTestSession(words: words)
        LearnerRecordingStore.shared.clear()
        loadSelfTestWord()
    }

    /// 取消自测（任何时候都可以），或看完完成页返回。回到普通练习，不留任何锁定状态。
    func endSelfTest() {
        if stage == .recording { cancelRecording() }
        mode = .practice
        selfTest = nil
        selfTestFinished = false
        LearnerRecordingStore.shared.clear()
        loadCurrent()
    }

    private func loadSelfTestWord() {
        guard let id = selfTest?.currentID, let lexeme = CorpusLoader.shared.lexeme(id: id) else {
            // 全部录完
            selfTestFinished = true
            currentLexeme = nil
            stage = .ready
            return
        }
        loadLexeme(lexeme)
    }

    // MARK: - 示范与回听（与录音三者互斥）

    /// 朗读示范。自测不提供示范。
    func playSample() {
        guard mode == .practice, !isBusy, let lexeme = currentLexeme else { return }
        if playing == .sample {          // 再点一次 = 停止
            stopAllPlayback()
            return
        }
        stopAllPlayback()
        let versionID = ResearchLexicon.versionID(for: lexeme.id)
        playing = .sample
        SpeechService.shared.speak(lexeme.hanzi, onStart: {
            // 字典 §8：model_audio_started 记的是**实际开始播放**，不是点击
            ResearchEventLog.shared.log(.modelAudioStarted, lexemeVersionID: versionID)
        }, onEnd: { [weak self] in
            if self?.playing == .sample { self?.playing = nil }
        })
    }

    /// 回听本次录音。返回**是否真的开始播放**——埋点看它，不看按钮点击。
    @discardableResult
    func replayOwnRecording() -> Bool {
        guard mode == .practice, !isBusy else { return false }
        if playing == .ownRecording {
            stopAllPlayback()
            return false
        }
        stopAllPlayback()
        let store = LearnerRecordingStore.shared
        guard store.hasRecording else { return false }
        do {
            let started = try LearnerAudioPlayer.shared.play(
                pcm: store.pcm, sampleRate: store.sampleRate,
                onFinish: { [weak self] in
                    if self?.playing == .ownRecording { self?.playing = nil }
                })
            if started {
                playing = .ownRecording
                // 该事件 attempt_id 必填；回听的总是刚才那一次录音
                if currentAttemptID != nil {
                    ResearchEventLog.shared.log(.learnerAudioStarted,
                                                attemptID: currentAttemptID,
                                                lexemeVersionID: lexemeVersionID)
                }
            }
            return started
        } catch {
            // 播放失败要让人看得见，不静默吞掉。已有的反馈不清除。
            if feedbackResult == nil { stage = .failed(.playback) }
            ResearchEventLog.shared.log(
                .operationError, attemptID: currentAttemptID,
                payload: ["stage": ResearchErrorStage.playback.rawValue,
                          "error_code": ResearchErrorCode.playbackError.rawValue])
            return false
        }
    }

    func stopAllPlayback() {
        SpeechService.shared.stopSpeaking()
        LearnerAudioPlayer.shared.stop()
        playing = nil
    }

    // MARK: - 建议与反馈模式

    /// 用户点击「练习建议」。**未点击不自动生成、也不计作已使用**（字典 §9）。
    func openAdvice() {
        guard mode == .practice else { return }
        currentAdvice = .make(result: feedbackResult, lexemeID: currentLexeme?.id)
        showAdvice = true
        AdviceRequestLog.shared.record(advice: currentAdvice, attemptID: currentAttemptID,
                                       lexemeVersionID: lexemeVersionID)
    }

    /// 记录反馈模式切换。只在用户**实际切换**时调用。
    ///
    /// ⚠ 已知缺口：字典 §8 规定本事件 `attempt_id` 必填，而切换器在首次录音之前
    /// 就可用——那时没有尝试，按字典只能不记，所以切换日志**系统性漏掉
    /// 「首次录音前的切换」**。这里遵守已冻结的字典，不偷偷传 nil 绕过校验。
    func logFeedbackModeChanged(from old: FeedbackStyle, to new: FeedbackStyle) {
        guard old != new, currentAttemptID != nil else { return }
        ResearchEventLog.shared.log(
            .feedbackModeChanged, attemptID: currentAttemptID,
            lexemeVersionID: lexemeVersionID,
            payload: ["from_mode": ResearchFeedbackMode(old).rawValue,
                      "to_mode": ResearchFeedbackMode(new).rawValue])
    }

    /// 结果**已经呈现在屏幕上**。由结果视图出现时调用，不是在算出结果时。
    ///
    /// 这一步才完成三件事：给尝试记下结果显示时间、记 `feedback_displayed` 事件、
    /// 累计一次合格练习。按尝试编号去重——视图重绘、旋转屏幕都不会重复计。
    func feedbackDidAppear() {
        guard mode == .practice, feedbackResult != nil, let id = currentAttemptID,
              !displayedAttemptIDs.contains(id) else { return }
        displayedAttemptIDs.insert(id)
        let tracked = ResearchAttemptLog.shared.isTracking(id)
        ResearchAttemptLog.shared.markResultDisplayed(id)
        guard tracked else { return }
        ResearchEventLog.shared.log(
            .feedbackDisplayed, attemptID: id, lexemeVersionID: lexemeVersionID,
            payload: ["mode": ResearchFeedbackMode(FeedbackStyle.current).rawValue])
        // 不要求通过：低分的有效结果照样计次
        SurveyCenter.recordQualifyingAttempt(id, taskType: .fixedWord, resultDisplayed: true)
    }

    /// 「再试一次」：清掉上次结果回到可录音状态
    func clearFeedbackForRetry() {
        guard !isBusy else { return }
        finishViewingFeedback()
        stopAllPlayback()
        feedbackResult = nil
        studentF0 = []
        stage = isReferenceReady ? .ready : .preparing
    }

    /// 用户结束了对当前反馈的查看（换词、再试、离开页面）。
    /// 使用后问卷的邀请只在这之后出现，不打断正在看的反馈或回听。
    func finishViewingFeedback() {
        guard mode == .practice, postSurveyInvitation == nil else { return }
        if let record = SurveyCenter.consumePostInvitationIfDue() {
            postSurveyInvitation = record
        }
    }

    /// 进入练习页时：上次达到条件但没来得及邀请的（比如 App 被杀），现在补上
    func presentPostInvitationIfDue() {
        guard feedbackResult == nil else { return }
        finishViewingFeedback()
    }

    // MARK: - 录音

    /// 点击录音键：没在录就开始，在录就停止并分析。全 App 统一「点一下开始、点一下停止」。
    func toggleRecording() {
        if stage == .recording {
            stopRecordingAndEvaluate()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard canRecord, stage != .recording, currentLexeme != nil else { return }
        // 麦克风权限在**首次实际录音前**申请（需求 R02），不在启动时。
        if usesMicrophone {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                break
            case .undetermined:
                Task { [weak self] in
                    let granted = await AVAudioApplication.requestRecordPermission()
                    guard let self else { return }
                    if granted { self.beginRecording() } else { self.stage = .failed(.microphoneDenied) }
                }
                return
            default:
                recordPermissionFailure()
                stage = .failed(.microphoneDenied)
                return
            }
        }
        beginRecording()
    }

    /// 从系统设置回来后重新检查麦克风权限（不需要重启 App）
    func recheckMicrophonePermission() {
        guard failure == .microphoneDenied else { return }
        if AVAudioApplication.shared.recordPermission == .granted {
            stage = isReferenceReady ? .ready : .preparing
        }
    }

    private func beginRecording() {
        guard let lexeme = currentLexeme, stage != .recording, stage != .analyzing else { return }
        // 参考未就绪时不能开始录音：否则看到的线 ≠ 评分的线
        guard isReferenceReady else { return }
        // 这里**不**触发使用后问卷的邀请：用户正要录音，不能弹东西抢走这一步。
        // 邀请留到他换词、点「再试一次」或离开页面时。
        // 示范、回听、录音三者互斥：先停播放，再由 AudioEngine 切到录音会话
        stopAllPlayback()

        accumulatedF0 = []
        studentF0 = []
        feedbackResult = nil
        lastCurveRefresh = .distantPast   // 让本次录音第一帧立即刷新曲线
        framer.reset()
        // 锁定参照：本次录音的显示与评分都用它
        lockedReference = referenceF0
        lockedReferenceType = referenceType

        // 一次尝试 = 一次开始录音（字典 §7）。重录生成新编号并关联上一次；
        // 上传重试不算新尝试。
        let attemptID = UUID()
        currentAttemptID = attemptID
        SurveyCenter.markPracticeStarted()
        ResearchAttemptLog.shared.begin(
            attemptID: attemptID,
            taskType: taskType,
            lexemeVersionID: ResearchLexicon.versionID(for: lexeme.id),
            // 自测时记该词此前练过几次（本机计数；换设备后的次数无从得知，
            // 所以这是「本机已知的既往练习次数」，不是该学习者的全部次数）
            priorPracticeCount: mode == .selfTest ? ToneAttemptStore.attempts(for: lexeme.id) : nil,
            retryOf: previousAttemptID)
        previousAttemptID = attemptID

        #if DEBUG
        (recorder as? SyntheticRecordingSource)?.tones = lexeme.tones
        #endif
        do {
            try recorder.start(duration: nil)
            stage = .recording
        } catch {
            // 启动失败必须给出可执行提示：否则学习者看到的是一个按了没反应的按钮
            let denied = usesMicrophone
                && AVAudioApplication.shared.recordPermission != .granted
            stage = .failed(denied ? .microphoneDenied : .microphoneUnavailable)
            persistTechnicalRetry(reason: failureReason(for: error), voicedFrameCount: 0)
            ResearchAttemptLog.shared.markFailed(
                attemptID, status: .recordingFailed,
                error: researchErrorCode(for: error))
        }
    }

    /// 权限被拒时也留一条技术失败记录，否则「没给麦克风权限」在数据里完全不可见
    private func recordPermissionFailure() {
        guard currentLexeme != nil else { return }
        persistTechnicalRetry(reason: .permissionDenied, voicedFrameCount: 0)
        ResearchEventLog.shared.log(
            .operationError, lexemeVersionID: lexemeVersionID,
            payload: ["stage": ResearchErrorStage.recording.rawValue,
                      "error_code": ResearchErrorCode.permissionDenied.rawValue])
    }

    /// 用户主动放弃这次录音（离开页面、取消自测）。不分析、不出结果、没有成绩。
    func cancelRecording() {
        guard stage == .recording else { return }
        recorder.stop()
        accumulatedF0 = []
        studentF0 = []
        LearnerRecordingStore.shared.clear()
        if let id = currentAttemptID { ResearchAttemptLog.shared.markCancelled(id) }
        flushPendingReference()
        stage = .ready
    }

    /// 录音被系统打断（来电、音频会话被占、切到后台）。安全停下并如实记为中断。
    func handleInterruption() {
        guard stage == .recording else { return }
        recorder.stop()
        accumulatedF0 = []
        studentF0 = []
        LearnerRecordingStore.shared.clear()
        if let id = currentAttemptID { ResearchAttemptLog.shared.markInterrupted(id) }
        persistTechnicalRetry(reason: .recordingInterrupted, voicedFrameCount: 0)
        flushPendingReference()
        stage = .failed(.interrupted)
    }

    /// 离开练习页。录音中则取消；播放一律停掉；结束对反馈的查看。
    func leavePage() {
        if stage == .recording { cancelRecording() }
        stopAllPlayback()
        finishViewingFeedback()
    }

    func stopRecordingAndEvaluate() {
        guard stage == .recording else { return }
        recorder.stop()
        stage = .analyzing
        let attemptID = currentAttemptID

        let cleaned = f0Extractor.clean(accumulatedF0)
        let voicedFrames = cleaned.filter { $0 != 0 }.count
        if let attemptID { ResearchAttemptLog.shared.markAnalyzing(attemptID) }

        // 技术性失败（没录好）与发音错误分开——不生成结果、不给等级，
        // 但仍落一条 technical_retry 记录，否则失败率在数据里完全不可见。
        guard voicedFrames >= minVoicedFrames else {
            studentF0 = []
            persistTechnicalRetry(reason: .insufficientVoicedFrames,
                                  voicedFrameCount: voicedFrames)
            // 新表**不写哨兵分**：metric/passed 保持 nil
            if let attemptID {
                ResearchAttemptLog.shared.markFailed(attemptID, status: .analysisFailed,
                                                     error: .noSignal)
            }
            flushPendingReference()
            stage = .failed(.noVoice)
            return
        }

        let normalized = f0Extractor.normalize(cleaned)

        // 评分用锁定参照，与录音期间显示的是同一条线
        let reference = lockedReference.isEmpty ? referenceF0 : lockedReference
        let score = dtwAnalyzer.distance(reference: reference, candidate: normalized)

        // 分数必须是有限数。NaN / Infinity 不是成绩：按分析失败处理，不显示、不入成绩。
        guard score.isFinite, score >= 0 else {
            studentF0 = []
            persistTechnicalRetry(reason: .analysisError, voicedFrameCount: voicedFrames)
            if let attemptID {
                ResearchAttemptLog.shared.markFailed(attemptID, status: .analysisFailed,
                                                     error: .analysisEngineError,
                                                     signal: .usable)
            }
            flushPendingReference()
            stage = .failed(.analysis)
            return
        }

        // 平调词走向闸门：DTW 归一化后尺度不变，判不出全一声的词被读成一路下滑。
        // **必须**喂原始 Hz 的 cleaned，不能喂 normalized（CLAUDE.md 禁令 15）。
        let tones = currentLexeme?.tones ?? []
        let droppedPitch = ToneDirectionGate.fails(hzTrack: cleaned, tones: tones)
        let grade = droppedPitch ? .fail : dtwAnalyzer.grade(dtwScore: score)

        // 按词累计尝试数（换词不归零）
        let lexemeID = currentLexeme?.id ?? "unknown"
        let attempt = ToneAttemptStore.increment(lexemeID)

        if let attemptID {
            ResearchAttemptLog.shared.markSucceeded(
                attemptID, metric: Double(score), passed: grade != .fail)
            // 积分由 manifest.reward_rule_version 开关，本轮保持关闭；自测从不发积分
            if mode == .practice {
                RewardLedger.shared.settle(attemptID: attemptID, lexemeID: lexemeID,
                                           passed: grade != .fail)
            }
        }

        let result = FeedbackResult(
            dtwScore: score,
            levelToneDropped: droppedPitch,
            grade: grade,
            attemptNumber: attempt,
            segments: buildSegments(student: normalized, reference: reference)
        )

        // 参照在本次录音中是否被换过——应恒为 false（不变式自检）
        let switched = !lockedReference.isEmpty && lockedReference != referenceF0
        persist(result,
                referenceType: lockedReferenceType,
                voicedFrameCount: voicedFrames,
                qualityFlag: score >= qualityFlagThreshold,
                referenceSwitched: switched)

        flushPendingReference()

        // 自测：照常算分入库，但**不向学习者呈现**任何评价；录完自动进下一词。
        guard mode == .practice else {
            studentF0 = []
            // 不呈现结果，故不填 resultDisplayedAt——使用后问卷的次数只认结果已显示者
            if let attemptID { ResearchAttemptLog.shared.finishWithoutDisplay(attemptID) }
            stage = .selfTestRecorded
            scheduleSelfTestAdvance()
            return
        }

        studentF0 = normalized
        consecutiveFailures = (grade == .fail) ? consecutiveFailures + 1 : 0
        feedbackResult = result
        stage = .feedback
        // 「结果已显示」与合格计次由视图在结果真正出现时触发，见 feedbackDidAppear()
    }

    /// 自测自动进入下一词。留出一拍让「已录到」可见，避免像是没录上。
    private func scheduleSelfTestAdvance() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, self.mode == .selfTest, self.stage == .selfTestRecorded else { return }
            self.selfTest?.completeCurrent()
            self.loadSelfTestWord()
        }
    }

    // MARK: - 系统打断

    private func observeInterruptions() {
        let center = NotificationCenter.default
        center.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                guard raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                self?.handleInterruption()
            }
            .store(in: &cancellables)
        // 切到后台：不允许后台持续录音。正在录的这一次如实记为中断。
        center.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleInterruption()
                self?.stopAllPlayback()
            }
            .store(in: &cancellables)
        // 从系统设置回来：重新检查麦克风权限，不需要重启 App
        center.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recheckMicrophonePermission() }
            .store(in: &cancellables)
    }

    // MARK: - 按字诊断

    /// 计算每个音节的分段 DTW + 方向提示。
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

    // MARK: - 持久化（旧业务表）

    /// 写进旧业务表 `phase` 列的值：普通练习 training，自测 self_test。
    /// 新版不再写 pretest / posttest。
    private var legacyPhase: TrainingPhase { mode == .selfTest ? .selfTest : .training }

    /// 映射到字典 §8 的固定错误码（研究库的固定枚举，服务端按白名单校验）
    private func researchErrorCode(for error: Error) -> ResearchErrorCode {
        if usesMicrophone,
           AVAudioApplication.shared.recordPermission != .granted { return .permissionDenied }
        guard let e = error as? AudioEngine.AudioEngineError else { return .unknown }
        switch e {
        case .engineStartFailed: return .analysisEngineError
        case .invalidInputFormat, .converterUnavailable: return .signalUnusable
        }
    }

    /// 把录音启动错误映射成匿名的失败原因（不含任何录音内容）
    private func failureReason(for error: Error) -> FailureReason {
        // 权限被拒最常见，且会伪装成 invalidInputFormat，所以先单独判掉
        if usesMicrophone,
           AVAudioApplication.shared.recordPermission != .granted {
            return .permissionDenied
        }
        guard let engineError = error as? AudioEngine.AudioEngineError else {
            return .analysisError
        }
        switch engineError {
        case .engineStartFailed:
            return .recordingInterrupted           // 会话被占用 / 路由切换
        case .invalidInputFormat, .converterUnavailable:
            return .lowSignalQuality               // 无可用输入设备 / 格式异常
        }
    }

    /// 落一条技术性失败记录：不生成等级、不计入发音成绩，只让失败率可见。
    private func persistTechnicalRetry(reason: FailureReason, voicedFrameCount: Int) {
        guard let profile = UserManager.shared.profile,
              let lexeme = currentLexeme else { return }
        SessionRepository.shared.saveTechnicalRetry(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            lexemeID: lexeme.id,
            // 不自增：没录上不算练过这个词
            attemptNumber: ToneAttemptStore.attempts(for: lexeme.id),
            timestamp: Date(),
            phase: legacyPhase.rawValue,
            wordSetID: lexeme.wordSet?.rawValue,
            assessmentSetVersion: mode == .selfTest ? AssessmentSet.version : nil,
            voicedFrameCount: voicedFrameCount,
            reason: reason
        )
    }

    private func persist(_ result: FeedbackResult,
                         referenceType: ReferenceType,
                         voicedFrameCount: Int,
                         qualityFlag: Bool,
                         referenceSwitched: Bool) {
        guard let profile = UserManager.shared.profile,
              let lexeme = currentLexeme else { return }
        // feedbackMode 记的是「这条记录当时用的哪种显示模式」，学习者自选，
        // **不是实验条件**——自选数据不得做组间比较。自测不显示任何反馈，故为 nil。
        // groupAssignment 是历史必填列，恒写 "n/a"。
        let shownStyle = mode == .practice ? FeedbackStyle.current.rawValue : nil
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
            phase: legacyPhase.rawValue,
            wordSetID: lexeme.wordSet?.rawValue,
            assessmentSetVersion: mode == .selfTest ? AssessmentSet.version : nil,
            feedbackMode: shownStyle,
            resultStatus: qualityFlag ? .qualityFlagged : .validResult
        )
    }

    // MARK: - 理想四声轮廓合成

    /// 按声调序列生成理想 F0 轮廓（Hz 量级）；归一化后作参照。
    static func idealContour(for tones: [Int]) -> [Float] {
        ToneContour.ideal(for: tones)
    }

    #if DEBUG
    /// 仅供测试：模拟「已开始过一次尝试」
    func beginAttemptForTesting() { currentAttemptID = UUID() }
    /// 仅供测试：直接置入一个结果，走「反馈已呈现」之后的逻辑
    func setFeedbackForTesting(_ result: FeedbackResult, attemptID: UUID) {
        currentAttemptID = attemptID
        feedbackResult = result
        stage = .feedback
    }
    #endif
}
