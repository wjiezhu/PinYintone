import AVFoundation

// 采样率固定 16 000 Hz，帧长 512，帧移 128（见 CLAUDE.md）
typealias AudioFrameCallback = ([Float]) -> Void

final class AudioEngine {
    /// 每帧（512 samples @16kHz）回调一次，在音频线程执行
    var onFrame: AudioFrameCallback?

    func start() throws {
        fatalError("TODO: 实现 — 配置 AVAudioSession + AVAudioEngine tap")
    }

    func stop() {
        fatalError("TODO: 实现 — 移除 tap，停止 engine")
    }
}
