import Combine
import Foundation

@MainActor
final class ToneTrainingViewModel: ObservableObject {
    @Published var currentLexeme: Lexeme?
    @Published var feedbackResult: FeedbackResult?
    @Published var isRecording: Bool = false
    @Published var studentF0: [Float] = []
    @Published var referenceF0: [Float] = []  // 母语者参照 F0

    private let audioEngine = AudioEngine()
    private let f0Extractor = F0Extractor()
    private let dtwAnalyzer = DTWAnalyzer()

    func loadNextLexeme() {
        fatalError("TODO: 实现 — 从 CorpusLoader 取下一词")
    }

    func toggleRecording() {
        fatalError("TODO: 实现")
    }

    private func evaluate() {
        fatalError("TODO: 实现 — DTW 评分 → FeedbackResult → 保存 TrainingSession")
    }
}
