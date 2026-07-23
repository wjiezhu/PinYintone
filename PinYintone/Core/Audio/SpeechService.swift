import AVFoundation
import Foundation

/// 母语者参照 F0 的来源，随训练记录上报以便分析时区分参照质量。
/// 优先级：真人录音 > TTS 合成 > 几何理想轮廓。
enum ReferenceType: String {
    case real    // 真人母语者录音（lexemes.json 的 audioFilename）
    case tts     // 系统 TTS 合成
    case ideal   // ToneContour 几何理想轮廓（兜底）
}

/// 系统 TTS（AVSpeechSynthesizer）服务：
/// 1) `speak` 朗读样例读音（zh-CN）；
/// 2) `synthesizeReferenceF0` 离线合成目标词 → YIN 提 F0 → 归一化，作母语者参照；
/// 3) `referenceF0FromBundledAudio` 从随包真人录音提 F0（质量优于 TTS，优先使用）。
/// 合成/加载失败或无声时返回空数组，调用方应依次回退。
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

    // MARK: - 真人母语者参照 F0（优先级最高）

    /// 从随包真人录音提取归一化 F0。
    /// - Parameter filename: `lexemes.json` 的 `audioFilename`（含或不含扩展名均可）
    /// - Returns: 归一化 F0；文件缺失/无声帧过少时返回 []（调用方回退到 TTS/理想轮廓）
    ///
    /// 说明：真人录音是 Mode B 有效性的上限——TTS 的 F0 偏平且带合成痕迹，
    /// 作"标准调型"不可靠，等于让学习者追一条不准的目标线。
    func referenceF0FromBundledAudio(named filename: String) async -> [Float] {
        guard !filename.isEmpty else { return [] }
        let samples = load16kMono(filename: filename)
        guard samples.count >= 512 else {
            #if DEBUG
            print("[SpeechService] 真人参照音缺失/过短 '\(filename)' → 回退")
            #endif
            return []
        }
        return f0Track(from: samples, tag: "真人音 \(filename)")
    }

    /// 读取 bundle 音频并重采样为 16 kHz 单声道 Float（与 CLAUDE.md 锁定采样率一致）
    private func load16kMono(filename: String) -> [Float] {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        let candidates = ext.isEmpty ? ["m4a", "wav", "caf", "mp3"] : [ext]

        var fileURL: URL?
        for e in candidates {
            if let u = Bundle.main.url(forResource: name, withExtension: e) { fileURL = u; break }
        }
        guard let url = fileURL,
              let file = try? AVAudioFile(forReading: url),
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000, channels: 1, interleaved: false)
        else { return [] }

        let srcFormat = file.processingFormat
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                           frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: inBuf)) != nil, inBuf.frameLength > 0
        else { return [] }

        // 已是目标格式则直接取样本
        if srcFormat.sampleRate == target.sampleRate, srcFormat.channelCount == 1,
           let ch = inBuf.floatChannelData {
            return Array(UnsafeBufferPointer(start: ch[0], count: Int(inBuf.frameLength)))
        }

        guard let conv = AVAudioConverter(from: srcFormat, to: target) else { return [] }
        let cap = AVAudioFrameCount(Double(inBuf.frameLength) * target.sampleRate / srcFormat.sampleRate) + 1024
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return [] }

        var fed = false
        _ = conv.convert(to: outBuf, error: nil) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return inBuf
        }
        guard let ch = outBuf.floatChannelData, outBuf.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(outBuf.frameLength)))
    }

    /// 逐帧提 F0 → clean → normalize（512 帧长 / 128 帧移，CLAUDE.md 锁定）
    private func f0Track(from samples: [Float], tag: String) -> [Float] {
        var hz: [Float] = []
        var i = 0
        while i + 512 <= samples.count {
            hz.append(f0Extractor.extract(frame: Array(samples[i..<(i + 512)])))
            i += 128
        }
        let voicedCount = hz.filter { $0 > 0 }.count
        guard voicedCount >= 3 else {
            #if DEBUG
            print("[SpeechService] 有声帧不足 (\(voicedCount)/\(hz.count)) \(tag) → 回退")
            #endif
            return []
        }
        #if DEBUG
        print("[SpeechService] OK \(tag): \(hz.count) 帧, \(voicedCount) 有声")
        #endif
        return f0Extractor.normalize(f0Extractor.clean(hz))
    }

    // MARK: - 合成母语者参照 F0

    /// 合成目标词并提取归一化 F0；有声帧过少时返回 []（让调用方回退）。
    func synthesizeReferenceF0(for text: String) async -> [Float] {
        let samples = await render16k(text)
        guard samples.count >= 512 else {
            #if DEBUG
            print("[SpeechService] TTS 合成失败 (samples=\(samples.count)) '\(text)' → 回退几何轮廓")
            #endif
            return []
        }
        // clean：TTS 提取的参照同样有八度错误/尖峰，先清理再归一化
        return f0Track(from: samples, tag: "TTS '\(text)'")
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
