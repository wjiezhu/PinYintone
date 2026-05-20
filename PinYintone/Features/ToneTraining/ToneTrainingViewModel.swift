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

    init() {
        // 帧化层每凑满 512 样本 → 提 F0 → 累积 → 刷新归一化曲线
        framer.onFrame = { [weak self] frame in
            guard let self else { return }
            let hz = self.f0Extractor.extract(frame: frame)
            Task { @MainActor in
                self.accumulatedF0.append(hz)
                self.studentF0 = self.f0Extractor.normalize(self.accumulatedF0)
            }
        }
        audioEngine.onChunk = { [weak self] pcm in
            self?.framer.feed(pcm)
        }
    }

    // MARK: - 词条

    func loadLexeme(_ lexeme: Lexeme) {
        currentLexeme = lexeme
        referenceF0 = f0Extractor.normalize(Self.idealContour(for: lexeme.tones))
        studentF0 = []
        accumulatedF0 = []
        feedbackResult = nil
        attemptCount = 0
    }

    func loadNext() {
        loadLexeme(CorpusLoader.shared.nextLexeme(category: .tone))
    }

    // MARK: - 录音

    func startRecording() {
        accumulatedF0 = []
        studentF0 = []
        feedbackResult = nil
        framer.reset()
        isRecording = true
        try? audioEngine.start()
    }

    func stopRecordingAndEvaluate() {
        audioEngine.stop()
        isRecording = false
        attemptCount += 1

        let normalized = f0Extractor.normalize(accumulatedF0)
        studentF0 = normalized
        let score = dtwAnalyzer.distance(reference: referenceF0, candidate: normalized)
        let grade = dtwAnalyzer.grade(dtwScore: score)
        let result = FeedbackResult(
            dtwScore: score,
            grade: grade,
            attemptNumber: attemptCount,
            toneErrors: []
        )
        feedbackResult = result
        persist(result)
    }

    // MARK: - 持久化

    private func persist(_ result: FeedbackResult) {
        guard let profile = UserManager.shared.profile,
              let lexeme = currentLexeme else { return }
        SessionRepository.shared.save(
            deviceID: profile.deviceID,
            classCode: profile.classCode,
            role: profile.role.rawValue,
            groupAssignment: GroupAssignment.shared.group.rawValue,
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
