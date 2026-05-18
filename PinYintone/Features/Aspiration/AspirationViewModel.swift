import Combine
import Foundation

@MainActor
final class AspirationViewModel: ObservableObject {
    @Published var triggerRate: Float = 0
    @Published var isRecording: Bool = false
    @Published var passed: Bool = false
    @Published var currentWord: String = ""

    private let audioEngine = AudioEngine()
    private let detector = AspirationDetector()

    func startCalibration() {
        fatalError("TODO: 实现 — 500ms 静音采集底噪")
    }

    func start() {
        fatalError("TODO: 实现 — 开始送气检测，600ms 窗口")
    }

    func stop() {
        fatalError("TODO: 实现 — 停止并保存 AspirationAttempt")
    }
}
