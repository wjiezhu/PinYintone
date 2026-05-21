import AVFoundation
import Foundation

/// 系统 TTS（AVSpeechSynthesizer）服务：
/// 1) `speak` 朗读样例读音（zh-CN）；
/// 2) `synthesizeReferenceF0` 离线合成目标词 → YIN 提 F0 → 归一化，作母语者参照。
/// 合成失败/无声时返回空数组，调用方应回退到 ToneContour 几何轮廓。
final class SpeechService {
    static let shared = SpeechService()

    private let player = AVSpeechSynthesizer()
    private let f0Extractor = F0Extractor()

    // 离线渲染期间持有 writer，避免提前释放
    private var renderers: [AVSpeechSynthesizer] = []
    private let renderersLock = NSLock()

    private init() {}

    private func zhVoice() -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice(language: "zh-CN") ?? AVSpeechSynthesisVoice(language: "zh-Hans")
    }

    // MARK: - 样例朗读

    /// 朗读文本（默认放慢语速便于模仿）。
    func speak(_ text: String, rate: Float = 0.4) {
        guard !text.isEmpty else { return }
        player.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = zhVoice()
        u.rate = rate
        player.speak(u)
    }

    // MARK: - 合成母语者参照 F0

    /// 合成目标词并提取归一化 F0；有声帧过少时返回 []（让调用方回退）。
    func synthesizeReferenceF0(for text: String) async -> [Float] {
        let samples = await render16k(text)
        guard samples.count >= 512 else { return [] }

        // 512 帧长 / 128 帧移（CLAUDE.md）逐帧提 F0
        var hz: [Float] = []
        var i = 0
        while i + 512 <= samples.count {
            hz.append(f0Extractor.extract(frame: Array(samples[i..<(i + 512)])))
            i += 128
        }
        guard hz.filter({ $0 > 0 }).count >= 3 else { return [] }
        return f0Extractor.normalize(hz)
    }

    /// 用 AVSpeechSynthesizer.write 离线渲染为 16kHz 单声道 Float PCM。
    private func render16k(_ text: String) async -> [Float] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Float], Never>) in
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false) else {
                cont.resume(returning: [])
                return
            }
            let utt = AVSpeechUtterance(string: text)
            utt.voice = zhVoice()
            utt.rate = 0.4

            let writer = AVSpeechSynthesizer()
            renderersLock.lock(); renderers.append(writer); renderersLock.unlock()

            let lock = NSLock()
            var out: [Float] = []
            var resumed = false
            var converter: AVAudioConverter?

            func finish() {
                lock.lock()
                let go = !resumed
                resumed = true
                let snapshot = out
                lock.unlock()
                guard go else { return }
                renderersLock.lock(); renderers.removeAll { $0 === writer }; renderersLock.unlock()
                cont.resume(returning: snapshot)
            }

            writer.write(utt) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 { finish(); return }   // 渲染结束标志
                if converter == nil { converter = AVAudioConverter(from: pcm.format, to: target) }
                guard let conv = converter else { return }
                let cap = AVAudioFrameCount(Double(pcm.frameLength) * target.sampleRate / pcm.format.sampleRate) + 1
                guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
                var fed = false
                _ = conv.convert(to: outBuf, error: nil) { _, status in
                    if fed { status.pointee = .noDataNow; return nil }
                    fed = true; status.pointee = .haveData; return pcm
                }
                if let ch = outBuf.floatChannelData, outBuf.frameLength > 0 {
                    let arr = Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
                    lock.lock(); out.append(contentsOf: arr); lock.unlock()
                }
            }

            // 超时兜底：若未收到结束回调，6s 后用已有数据返回
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) { finish() }
        }
    }
}
