import AVFoundation
import Combine
import Foundation

/// 送气练习的判定规则。送气音要爆破，不送气音不要爆破，所以同一条通关线方向相反。
nonisolated enum AspirationRule {
    /// CLAUDE.md 锁定的触发率通关线
    static let threshold: Float = 0.6

    static func passes(aspirated: Bool, peakRate: Float) -> Bool {
        aspirated ? peakRate >= threshold : peakRate < threshold
    }
}

/// 送气练习业务逻辑：学习者点开始 → 500ms 底噪校准 → 600ms 滑动窗口检测 →
/// 学习者点停止 → 按词的送气类型判定 → 保存记录。
/// 参数遵循 CLAUDE.md：阈值 = 底噪 + 15 dB，触发率通关线 0.6。
///
/// 进页面、换词都不开麦，只有点了开始才录。
@MainActor
final class AspirationViewModel: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    enum Stage: Equatable { case idle, calibrating, recording, result }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var currentLexeme: Lexeme?
    /// 当前 600ms 窗口的触发率
    @Published private(set) var triggerRate: Float = 0
    /// 这次录音到目前为止的最高触发率。判定看它：爆破只有一瞬间，停止时窗口早已回落
    @Published private(set) var peakRate: Float = 0
    /// 本次结果；还没有结果时为 nil
    @Published private(set) var passed: Bool?
    /// 技术性失败的可执行提示。**不得静默失败**（禁令 11）。
    @Published private(set) var retryHint: String?

    var isActive: Bool { stage == .calibrating || stage == .recording }
    /// 词的送气类型。语料里每个送气词条都有；缺失时按送气音处理
    var isAspirated: Bool { currentLexeme?.aspirationTarget?.aspirated ?? true }

    private let recorder: RecordingSource
    private let usesMicrophone: Bool
    private let detector = AspirationDetector()

    private let calibrationFrameCount = 5        // 500ms = 5 × 0.1s 帧
    private let windowSize = 6                   // 600ms = 6 × 0.1s 帧
    private var window: [[Float]] = []
    private var calibrationFrames: [[Float]] = []
    /// 录音里有没有听到声音。没有就是技术失败，**不得计入发音成绩**（禁令 9），
    /// 也不能算成「不送气做对了」。
    private var heardVoice = false

    /// 默认参数会在调用方的隔离域里求值，所以这里用可选值（同 ToneTrainingViewModel）
    init(recorder: RecordingSource? = nil) {
        let source = recorder ?? RecordingSourceFactory.make()
        self.recorder = source
        usesMicrophone = source is AudioEngine
        source.onChunk = { [weak self] pcm in
            let frame = AudioEngine.floatSamples(from: pcm)
            Task { @MainActor in self?.process(frame) }
        }
    }

    // MARK: - 词条

    func loadNextLexeme() {
        guard !isActive else { return }
        currentLexeme = CorpusLoader.shared.nextLexeme(category: .aspiration)
        resetResult()
        retryHint = nil
        stage = .idle
    }

    private func resetResult() {
        triggerRate = 0
        peakRate = 0
        passed = nil
        window = []
        calibrationFrames = []
        heardVoice = false
    }

    // MARK: - 开始 / 停止

    /// 点录音键：没在录就开始，在录就停止。全 App 统一「点一下开始、点一下停止」。
    func toggleRecording() {
        if isActive { stopAndEvaluate() } else { start() }
    }

    private func start() {
        guard currentLexeme != nil else { return }
        // 麦克风权限在首次实际录音前申请（需求 R02）。拒绝的话下面的启动会失败并给出提示。
        if usesMicrophone, MicPermission.state == .undetermined {
            Task { [weak self] in
                _ = await MicPermission.request()
                self?.beginRecording()
            }
            return
        }
        beginRecording()
    }

    private func beginRecording() {
        guard !isActive else { return }
        resetResult()
        retryHint = nil
        do {
            try recorder.start(duration: nil)
            stage = .calibrating
        } catch {
            stage = .idle
            // 禁令 11：录音启动失败必须给出可执行重录提示
            retryHint = NSLocalizedString("tone_retry_mic_unavailable", comment: "")
        }
    }

    /// 点了停止：判定并保存。校准没结束或没出声都不是成绩，只提示重录。
    func stopAndEvaluate() {
        guard isActive else { return }
        let wasCalibrating = stage == .calibrating
        recorder.stop()
        guard !wasCalibrating else {
            stage = .idle
            retryHint = NSLocalizedString("aspiration_stopped_early", comment: "")
            return
        }
        guard heardVoice else {
            stage = .idle
            retryHint = NSLocalizedString("tone_retry_no_voice", comment: "")
            return
        }
        let result = AspirationRule.passes(aspirated: isAspirated, peakRate: peakRate)
        passed = result
        stage = .result
        persist(passed: result)
    }

    /// 离开页面：录音中就放弃这一次，不判定、不留记录。
    func leavePage() {
        guard isActive else { return }
        recorder.stop()
        stage = .idle
    }

    // MARK: - 校准（前 500ms 采底噪）与检测（600ms 滑动窗口）

    private func process(_ frame: [Float]) {
        switch stage {
        case .calibrating:
            calibrationFrames.append(frame)
            if calibrationFrames.count >= calibrationFrameCount {
                detector.calibrateBaseline(frames: calibrationFrames)
                stage = .recording
            }
        case .recording:
            if detector.isAudible(frame: frame) { heardVoice = true }
            window.append(frame)
            if window.count > windowSize { window.removeFirst() }
            // 分母固定为窗口的 6 帧：刚开始只收到 1 帧时，1/1 = 100% 会让任何一声都算通过
            triggerRate = detector.triggerRate(frames: window)
                * Float(window.count) / Float(windowSize)
            peakRate = max(peakRate, triggerRate)
        case .idle, .result:
            break     // 停止之后才到的帧不算
        }
    }

    // MARK: - 持久化

    private func persist(passed: Bool) {
        guard let profile = UserManager.shared.profile, let lex = currentLexeme else { return }
        AspirationRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            targetWord: lex.hanzi,
            triggerRate: Double(peakRate),
            passed: passed,
            timestamp: Date(),
            phase: TrainingPhase.training.rawValue
        )
    }
}
