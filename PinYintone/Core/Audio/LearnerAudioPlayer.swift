import AVFoundation
import Foundation

/// 回听：播放学习者本人刚才的录音。
///
/// 事件口径（字段字典 §8）：`learner_audio_started` 必须在**实际开始播放**时记，
/// 「只点击播放但播放失败不记 audio_started」。因此 `play` 的返回值表示
/// **是否真的开始播了**，调用方据此决定要不要埋点——不能点了就记。
///
/// 零第三方依赖：AVFoundation 是系统框架（CLAUDE.md 禁令 5）。
@MainActor
final class LearnerAudioPlayer {
    static let shared = LearnerAudioPlayer()

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var attached = false

    private init() {}

    enum PlaybackError: Error {
        case emptyRecording
        case formatUnavailable
        case engineStartFailed(Error)
    }

    private(set) var isPlaying = false

    /// 播放给定 PCM。
    /// - Returns: 播放**确实开始**为 true；未开始（含失败）为 false。
    /// - Throws: 失败原因，供上层映射到 `playback_error` 埋点。
    @discardableResult
    func play(pcm: [Int16], sampleRate: Double,
              onFinish: (() -> Void)? = nil) throws -> Bool {
        guard !pcm.isEmpty else { throw PlaybackError.emptyRecording }

        stop()

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw PlaybackError.formatUnavailable
        }
        // 复用录音链路已有的 Int16 → Float 归一化，避免两处各写一份换算
        let floats = AudioEngine.floatSamples(from: pcm)
        floats.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: floats.count) }
        buffer.frameLength = AVAudioFrameCount(pcm.count)

        // 录音时会话是 .record，放音前必须切回可播放的类别
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try? session.setActive(true)

        if !attached {
            engine.attach(node)
            attached = true
        }
        engine.connect(node, to: engine.mainMixerNode, format: format)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            throw PlaybackError.engineStartFailed(error)
        }

        node.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in
                self?.isPlaying = false
                onFinish?()
            }
        }
        node.play()

        // 「实际开始播放」的操作定义：引擎已跑起来且播放节点报告正在播。
        // 这不等于学习者听完了——字典明确「播放开始不证明完整听完」。
        isPlaying = engine.isRunning && node.isPlaying
        return isPlaying
    }

    func stop() {
        if node.isPlaying { node.stop() }
        if engine.isRunning { engine.stop() }
        isPlaying = false
    }
}
