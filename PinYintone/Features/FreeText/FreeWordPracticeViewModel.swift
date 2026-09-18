import AVFoundation
import Combine
import Foundation

/// 关卡 3 逐词练习业务逻辑：AudioEngine → AudioFramer → F0Extractor 实时取 F0，
/// 理想声调形状由 PinyinConverter 取声调 → ToneContour 合成（与声调训练一致）。
@MainActor
final class FreeWordPracticeViewModel: ObservableObject {
    @Published var studentF0: [Float] = []
    @Published var idealShape: [Float] = []     // 理想声调轮廓（归一化）
    @Published var currentTones: [Int] = []
    @Published var isRecording: Bool = false
    @Published var feedbackResult: FeedbackResult?   // 录音结束后的百分制评分
    /// 录音起不来时的可执行提示。**不得为 nil 地静默失败**——
    /// CLAUDE.md 禁令 11：否则学习者看到的是一个按了没反应的按钮。
    @Published var retryHint: String?

    /// 本次尝试的研究编号
    private(set) var currentAttemptID: UUID?

    /// 由 View 注入的原始整段文本（用于研究数据 originalText 字段）
    var originalText: String = ""

    private let audioEngine = AudioEngine()
    private let framer = AudioFramer()
    private let f0Extractor = F0Extractor()
    private let dtwAnalyzer = DTWAnalyzer()
    private let pinyinConverter = PinyinConverter()
    private var accumulated: [Float] = []
    private var currentWord: String = ""
    private var recordingStart = Date()
    /// 实时曲线刷新节流（同 ToneTrainingViewModel）：帧移 128 samples ≈ 每 8ms 一帧，
    /// 全量 normalize + Canvas 重绘会拖垮主线程 → watchdog 终止进程，节流到 ~12fps。
    private var lastCurveRefresh: Date = .distantPast
    private let curveRefreshInterval: TimeInterval = 0.08   // ≈12fps

    init() {
        framer.onFrame = { [weak self] frame in
            guard let self else { return }
            let hz = self.f0Extractor.extract(frame: frame)
            Task { @MainActor in
                self.accumulated.append(hz)
                if Date().timeIntervalSince(self.lastCurveRefresh) >= self.curveRefreshInterval {
                    self.lastCurveRefresh = Date()
                    // clean：八度纠错 + 去尖峰，避免曲线出现 2× 跳变毛刺
                    self.studentF0 = self.f0Extractor.normalize(
                        self.f0Extractor.clean(self.accumulated))
                }
            }
        }
        audioEngine.onChunk = { [weak self] pcm in self?.framer.feed(pcm) }
    }

    /// 切换到某个词：计算声调与理想形状（不录音）
    func prepare(word: String) {
        currentWord = word
        currentTones = pinyinConverter.toneSequence(for: word)
        // 即时占位：几何理想轮廓；随后异步升级为 TTS 合成参照
        idealShape = f0Extractor.normalize(ToneContour.ideal(for: currentTones))
        studentF0 = []
        accumulated = []
        feedbackResult = nil
        isRecording = false

        let tones = currentTones
        Task { [weak self] in
            // 自由文本无法预录真人音，只能用 TTS；传入 PinyinConverter 推出的声调
            // 以消除句调下倾（否则参照线会一路下滑，教错声调）
            let tts = await SpeechService.shared.synthesizeReferenceF0(for: word, tones: tones)
            await MainActor.run {
                guard let self, self.currentWord == word, !tts.isEmpty else { return }
                self.idealShape = tts
            }
        }
    }

    /// 朗读样例读音
    func playSample() {
        guard !currentWord.isEmpty else { return }
        SpeechService.shared.speak(currentWord)
    }

    func toggleRecording(targetWord: String) {
        isRecording ? stopRecording() : startRecording(targetWord: targetWord)
    }

    func reset() {
        studentF0 = []
        accumulated = []
        isRecording = false
    }

    // MARK: - 私有

    private func startRecording(targetWord: String) {
        if currentWord != targetWord { prepare(word: targetWord) }
        accumulated = []
        studentF0 = []
        feedbackResult = nil
        framer.reset()
        lastCurveRefresh = .distantPast
        recordingStart = Date()
        retryHint = nil
        // 一次尝试 = 一次开始录音。自由文本**不带词条编号、不存用户原文**
        // （字典 §7：free_text 的 lexeme_version_id 为 NULL）。
        let attemptID = UUID()
        currentAttemptID = attemptID
        ResearchAttemptLog.shared.begin(attemptID: attemptID, taskType: .freeText,
                                        lexemeVersionID: nil, priorPracticeCount: nil)
        isRecording = true
        do {
            try audioEngine.start()
        } catch {
            isRecording = false
            // 禁令 11：录音启动失败必须给出可执行提示，不得静默吞掉
            retryHint = NSLocalizedString("tone_retry_mic_unavailable", comment: "")
            ResearchAttemptLog.shared.markFailed(
                attemptID, status: .recordingFailed,
                error: Self.researchErrorCode(for: error))
            ResearchEventLog.shared.log(
                .operationError, attemptID: attemptID,
                payload: ["stage": ResearchErrorStage.recording.rawValue,
                          "error_code": Self.researchErrorCode(for: error).rawValue])
        }
    }

    /// 与关卡 2 同一套映射：服务端按固定错误码白名单校验
    private static func researchErrorCode(for error: Error) -> ResearchErrorCode {
        if AVAudioApplication.shared.recordPermission != .granted { return .permissionDenied }
        guard let e = error as? AudioEngine.AudioEngineError else { return .unknown }
        switch e {
        case .engineStartFailed: return .analysisEngineError
        case .invalidInputFormat, .converterUnavailable: return .signalUnusable
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        isRecording = false
        let cleaned = f0Extractor.clean(accumulated)
        let attemptID = currentAttemptID
        if let attemptID { ResearchAttemptLog.shared.markAnalyzing(attemptID) }

        // 有声帧过少：技术性失败，不生成发音成绩（禁令 9）。
        // 新表的 metric/passed 保持 nil，**不填零分替代**。
        let voiced = cleaned.filter { $0 != 0 }.count
        guard voiced >= Self.minVoicedFrames else {
            studentF0 = []
            retryHint = NSLocalizedString("tone_retry_no_voice", comment: "")
            if let attemptID {
                ResearchAttemptLog.shared.markFailed(attemptID, status: .analysisFailed,
                                                     error: .noSignal)
            }
            return
        }

        let normalized = f0Extractor.normalize(cleaned)
        studentF0 = normalized
        // 与理想声调形状比对，给出百分制评分
        let dtw = dtwAnalyzer.distance(reference: idealShape, candidate: normalized)
        let grade = dtwAnalyzer.grade(dtwScore: dtw)
        feedbackResult = FeedbackResult(
            dtwScore: dtw,
            grade: grade,
            attemptNumber: 1,
            segments: []
        )
        if let attemptID {
            ResearchAttemptLog.shared.markSucceeded(attemptID, metric: Double(dtw),
                                                    passed: grade != .fail)
            // 结果已渲染；但自由文本**不计入**使用后问卷的 5 次阈值
            ResearchAttemptLog.shared.markResultDisplayed(attemptID)
        }
        persist()
    }

    /// 与关卡 2 同口径（`ToneTrainingViewModel.minVoicedFrames`）
    private static let minVoicedFrames = 5

    private func persist() {
        guard let profile = UserManager.shared.profile, !currentWord.isEmpty else { return }
        FreeTextRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            originalText: originalText.isEmpty ? currentWord : originalText,
            tokenizedWord: currentWord,
            pinyin: pinyinConverter.pinyin(for: currentWord),
            toneSequence: currentTones,
            f0Track: accumulated,          // 原始 Hz 序列（含 0 无声帧）
            duration: Date().timeIntervalSince(recordingStart),
            timestamp: Date(),
            // 关卡 3 不参与 A/B（无 groupAssignment 字段），只记录阶段供筛选
            phase: ToneSequencer.shared.phase.rawValue
        )
    }
}
