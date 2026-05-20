import Foundation

/// 帧化适配层：把 AudioEngine 的 16-bit PCM 分片（1600 采样 / 0.1 s）
/// 重组为 F0Extractor 所需的滑动帧。
/// 参数遵循 CLAUDE.md：帧长 512、帧移 128（75% 重叠）。
///
/// 用法：
/// ```
/// let framer = AudioFramer()
/// framer.onFrame = { frame in let f0 = extractor.extract(frame: frame) }
/// audioEngine.onChunk = { chunk in framer.feed(chunk) }
/// ```
final class AudioFramer {

    let frameSize: Int   // 512（CLAUDE.md）
    let hopSize: Int     // 128（CLAUDE.md）

    /// 每凑满一帧（512 样本）回调一次，已归一化为 [-1, 1] 的 Float
    var onFrame: (([Float]) -> Void)?

    private var buffer: [Float] = []

    init(frameSize: Int = 512, hopSize: Int = 128) {
        self.frameSize = frameSize
        self.hopSize = hopSize
    }

    /// 送入一段 16-bit PCM（通常来自 AudioEngine.onChunk）。
    func feed(_ pcm: [Int16]) {
        buffer.append(contentsOf: AudioEngine.floatSamples(from: pcm))
        while buffer.count >= frameSize {
            onFrame?(Array(buffer.prefix(frameSize)))
            buffer.removeFirst(hopSize)
        }
    }

    /// 清空内部缓冲（每次录音开始前调用）。
    func reset() {
        buffer.removeAll(keepingCapacity: true)
    }
}
