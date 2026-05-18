import Combine
import Foundation

@MainActor
final class FreeWordPracticeViewModel: ObservableObject {
    @Published var studentF0: [Float] = []
    @Published var idealShape: [Float] = []   // AVSpeechSynthesizer TTS F0
    @Published var isRecording: Bool = false

    private let audioEngine = AudioEngine()
    private let f0Extractor = F0Extractor()
    private var accumulated: [Float] = []
    private var currentWord: String = ""

    func toggleRecording(targetWord: String) {
        fatalError("TODO: 实现")
    }

    func reset() {
        fatalError("TODO: 实现")
    }

    private func startRecording(targetWord: String) {
        fatalError("TODO: 实现 — 合成 TTS F0 作理想形状 + 启动 AudioEngine")
    }

    private func stopRecording() {
        fatalError("TODO: 实现 — 停止录音 + 保存 FreeTextRecord")
    }

    /// 用 AVSpeechSynthesizer 合成目标词，提取 F0 作为理想声调形状
    private func synthesizeIdealShape(for word: String) async -> [Float] {
        fatalError("TODO: 实现 — AVSpeechUtterance(zh-CN, rate=0.4) → 录制 → YIN F0")
    }
}
