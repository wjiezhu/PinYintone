import Foundation

/// 录音来源。正常情况下就是 `AudioEngine`（麦克风）。
///
/// 抽成协议只为一件事：界面自动化测试需要在模拟器里稳定地「录到」一段
/// 有基频的声音，而模拟器的音频输入不可控。开发构建里可以换成合成信号，
/// **正式构建里只有 `AudioEngine` 这一个实现**。
protocol RecordingSource: AnyObject {
    var onChunk: (([Int16]) -> Void)? { get set }
    var onFinish: (([Int16]) -> Void)? { get set }
    func start(duration: TimeInterval?) throws
    @discardableResult func stop() -> [Int16]
}

extension AudioEngine: RecordingSource {}

enum RecordingSourceFactory {
    static func make() -> RecordingSource {
        #if DEBUG
        if let mode = SyntheticRecordingSource.Mode.fromEnvironment {
            return SyntheticRecordingSource(mode: mode)
        }
        #endif
        return AudioEngine()
    }

    /// 是否在用合成信号（仅开发构建可能为 true）。用于跳过麦克风权限与 TTS 参照合成——
    /// 两者在无人值守的模拟器里都不可靠。
    static var isSynthetic: Bool {
        #if DEBUG
        return SyntheticRecordingSource.Mode.fromEnvironment != nil
        #else
        return false
        #endif
    }
}

#if DEBUG
/// 仅开发构建：用合成的正弦信号代替麦克风，供界面测试走通「录音 → 分析 → 反馈」。
///
/// 由启动环境变量 `PT_SYNTHETIC_AUDIO` 开启：
/// - `match`：基频按目标声调的理想轮廓变化，能得到一次有效分析
/// - `silent`：全零，用来走「没录到声音」的技术失败路径
///
/// 它产生的是**测试数据**：开发构建下纳入的参与者一律 is_test=true，
/// 正式导出默认排除。本类型不存在于正式构建。
final class SyntheticRecordingSource: RecordingSource {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    enum Mode: String {
        case match, silent
        static var fromEnvironment: Mode? {
            ProcessInfo.processInfo.environment["PT_SYNTHETIC_AUDIO"].flatMap(Mode.init(rawValue:))
        }
    }

    var onChunk: (([Int16]) -> Void)?
    var onFinish: (([Int16]) -> Void)?
    /// 目标声调，录音开始前由调用方设置
    var tones: [Int] = [1]

    private let mode: Mode
    private let sampleRate = 16_000.0
    private let chunkSize = 1600
    /// 有声部分的总时长；之后输出静音，录多久都得到同一段内容
    private let voicedSeconds = 0.9
    private var timer: Timer?
    private var produced: [Int16] = []
    private var sampleIndex = 0
    private var phase = 0.0

    init(mode: Mode) { self.mode = mode }

    func start(duration: TimeInterval?) throws {
        timer?.invalidate()
        produced = []
        sampleIndex = 0
        phase = 0
        let contour = ToneContour.ideal(for: tones).map(Double.init)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit(contour: contour) }
        }
    }

    private func emit(contour: [Double]) {
        var chunk = [Int16](repeating: 0, count: chunkSize)
        let voicedSamples = Int(voicedSeconds * sampleRate)
        if mode == .match, !contour.isEmpty {
            for i in 0..<chunkSize {
                let n = sampleIndex + i
                guard n < voicedSamples else { break }
                let pos = Double(n) / Double(voicedSamples) * Double(contour.count - 1)
                let lo = Int(pos), hi = min(lo + 1, contour.count - 1)
                let hz = contour[lo] + (contour[hi] - contour[lo]) * (pos - Double(lo))
                phase += 2 * Double.pi * hz / sampleRate
                chunk[i] = Int16(sin(phase) * 9000)
            }
        }
        sampleIndex += chunkSize
        produced.append(contentsOf: chunk)
        onChunk?(chunk)
    }

    @discardableResult
    func stop() -> [Int16] {
        timer?.invalidate()
        timer = nil
        let buffer = produced
        DispatchQueue.main.async { [weak self] in self?.onFinish?(buffer) }
        return buffer
    }
}
#endif
