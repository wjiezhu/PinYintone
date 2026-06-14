import Combine
import Foundation

/// 送气训练业务逻辑：500ms 底噪校准 → 600ms 滑动窗口送气检测 → 保存记录。
/// 参数遵循 CLAUDE.md：阈值 = 底噪 + 15 dB，触发率通关线 ≥ 0.6。
@MainActor
final class AspirationViewModel: ObservableObject {
    @Published var currentLexeme: Lexeme?
    @Published var triggerRate: Float = 0
    @Published var triggered: Bool = false      // 当前帧是否超阈
    @Published var calibrated: Bool = false
    @Published var isRecording: Bool = false
    @Published var passed: Bool = false

    private let audioEngine = AudioEngine()
    private let detector = AspirationDetector()

    private let windowSize = 6                   // 600ms = 6 × 0.1s 帧
    private var window: [[Float]] = []
    private var calibrationFrames: [[Float]] = []

    // MARK: - 词条

    func loadNextLexeme() {
        currentLexeme = CorpusLoader.shared.nextLexeme(category: .aspiration)
        resetState()
        startCalibration()
    }

    private func resetState() {
        triggerRate = 0
        triggered = false
        passed = false
        window = []
    }

    // MARK: - 校准（前 500ms 采底噪）

    func startCalibration() {
        calibrated = false
        calibrationFrames = []
        audioEngine.onChunk = { [weak self] pcm in
            let frame = AudioEngine.floatSamples(from: pcm)
            Task { @MainActor in self?.calibrationFrames.append(frame) }
        }
        audioEngine.onFinish = { [weak self] _ in
            guard let self else { return }
            self.detector.calibrateBaseline(frames: self.calibrationFrames)
            self.calibrated = true
            self.startDetection()
        }
        do {
            try audioEngine.start(duration: 0.5)
        } catch {
            calibrated = false
        }
    }

    // MARK: - 检测（600ms 滑动窗口）

    private func startDetection() {
        resetState()
        isRecording = true
        audioEngine.onFinish = nil
        audioEngine.onChunk = { [weak self] pcm in
            let frame = AudioEngine.floatSamples(from: pcm)
            Task { @MainActor in self?.process(frame) }
        }
        do {
            try audioEngine.start()
        } catch {
            isRecording = false
        }
    }

    private func process(_ frame: [Float]) {
        window.append(frame)
        if window.count > windowSize { window.removeFirst() }
        triggerRate = detector.triggerRate(frames: window)
        triggered = detector.detect(frame: frame)
        if triggerRate >= 0.6, !passed {
            passed = true
            stop()
        }
    }

    func stop() {
        audioEngine.stop()
        isRecording = false
        persist()
    }

    // MARK: - 持久化

    private func persist() {
        guard let profile = UserManager.shared.profile, let lex = currentLexeme else { return }
        AspirationRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            targetWord: lex.hanzi,
            triggerRate: Double(triggerRate),
            passed: passed,
            timestamp: Date()
        )
    }
}
