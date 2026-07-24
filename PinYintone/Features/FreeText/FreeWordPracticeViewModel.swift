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
        isRecording = true
        do {
            try audioEngine.start()
        } catch {
            isRecording = false
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        isRecording = false
        let normalized = f0Extractor.normalize(f0Extractor.clean(accumulated))
        studentF0 = normalized
        // 与理想声调形状比对，给出百分制评分
        let dtw = dtwAnalyzer.distance(reference: idealShape, candidate: normalized)
        feedbackResult = FeedbackResult(
            dtwScore: dtw,
            grade: dtwAnalyzer.grade(dtwScore: dtw),
            attemptNumber: 1,
            segments: []
        )
        persist()
    }

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
            timestamp: Date()
        )
    }
}
