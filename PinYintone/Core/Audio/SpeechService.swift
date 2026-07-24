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
        // 真人录音本就是孤立字本调，不做下倾矫正（tones 传空）
        return f0Track(from: samples, tag: "真人音 \(filename)", tones: [])
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

    /// 逐帧提 F0 → clean → 去句调下倾 → normalize（512 帧长 / 128 帧移，CLAUDE.md 锁定）
    /// - Parameter tones: 目标声调序列。传入后可消除 TTS 的句调下倾并校验结果可信度；
    ///                    传空数组则跳过这两步（与旧行为一致）。
    private func f0Track(from samples: [Float], tag: String, tones: [Int]) -> [Float] {
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

        var cleaned = f0Extractor.clean(hz)
        if !tones.isEmpty {
            cleaned = removeExcessDeclination(cleaned, tones: tones)
            guard !contourContradictsTones(cleaned, tones: tones) else {
                #if DEBUG
                print("[SpeechService] \(tag) 走向与目标声调 \(tones) 矛盾 → 回退理想轮廓")
                #endif
                return []
            }
        }
        #if DEBUG
        print("[SpeechService] OK \(tag): \(hz.count) 帧, \(voicedCount) 有声, tones=\(tones)")
        #endif
        return f0Extractor.normalize(cleaned)
    }

    // MARK: - 句调下倾矫正

    /// 消除 TTS 的**多余**下倾。
    ///
    /// TTS（AVSpeechSynthesizer）会把词当成一句话来读，叠加句子级的下倾（declination）
    /// 与句末降调。结果是像「医生」(1+1 全高平) 这种词被合成成一路下滑的曲线——
    /// 学习者照着模仿会学错调，DTW 也会拿这条错线打分。
    ///
    /// 直接做全局去趋势会误伤本来就该下降的词（如「现在」4+4）。因此这里以
    /// **同声调序列的理想轮廓**为基准，只减去 TTS 相对理想轮廓**多出来**的那部分斜率：
    /// 1+1 的理想轮廓近乎水平 → 下倾被扣掉；4+4 的理想轮廓本就下行 → 几乎不动。
    ///
    /// 斜率在各自标准化（z）后比较以消除音域差异，再按 TTS 自身标准差换算回 Hz。
    private func removeExcessDeclination(_ track: [Float], tones: [Int]) -> [Float] {
        let positions = track.indices.filter { track[$0] > 0 }
        let n = positions.count
        guard n >= 6 else { return track }

        let ttsHz = positions.map { track[$0] }
        guard let (tMean, tSD) = meanSD(ttsHz), tSD > 0 else { return track }

        // 理想轮廓重采样到相同点数，用于估计"这组声调本身应有的"斜率
        let ideal = resample(ToneContour.ideal(for: tones), to: n)
        guard let (_, iSD) = meanSD(ideal), iSD > 0 else { return track }

        let xs = (0..<n).map { Float($0) }
        let slopeTTS = slope(xs, ttsHz.map { ($0 - tMean) / tSD })
        let slopeIdeal = slope(xs, ideal.map { ($0 - (meanSD(ideal)?.0 ?? 0)) / iSD })
        let excessZ = slopeTTS - slopeIdeal
        guard abs(excessZ) > 1e-4 else { return track }

        // 以序列中点为轴做校正，避免整体平移（平移不影响 z-score，但保持数值稳健）
        let mid = Float(n - 1) / 2
        var out = track
        for (k, pos) in positions.enumerated() {
            let delta = excessZ * tSD * (Float(k) - mid)
            out[pos] = max(track[pos] - delta, 1)   // 保底为正，避免被误判成无声帧
        }
        return out
    }

    /// 校验矫正后的走向是否与目标声调**明显矛盾**（如二声却在下降）。
    /// 只在半数以上音节矛盾时才判定不可信，避免把可用的参照误杀。
    private func contourContradictsTones(_ track: [Float], tones: [Int]) -> Bool {
        let voiced = track.filter { $0 > 0 }
        let n = tones.count
        guard n > 0, voiced.count >= n * 3 else { return false }
        guard let (_, sd) = meanSD(voiced), sd > 0 else { return false }

        var checked = 0, contradictions = 0
        for i in 0..<n {
            let seg = Array(voiced[(voiced.count * i / n)..<(voiced.count * (i + 1) / n)])
            guard seg.count >= 3 else { continue }
            let third = max(1, seg.count / 3)
            let head = seg.prefix(third).reduce(0, +) / Float(third)
            let tail = seg.suffix(third).reduce(0, +) / Float(third)
            let deltaZ = (tail - head) / sd

            switch tones[i] {
            case 2: checked += 1; if deltaZ < -0.6 { contradictions += 1 }   // 该升却明显降
            case 4: checked += 1; if deltaZ > 0.6  { contradictions += 1 }   // 该降却明显升
            case 1: checked += 1; if abs(deltaZ) > 1.6 { contradictions += 1 } // 该平却大起大落
            default: break   // 三声（曲折）与轻声不做方向判定
            }
        }
        return checked > 0 && contradictions * 2 > checked
    }

    // MARK: - 数值小工具

    private func meanSD(_ xs: [Float]) -> (Float, Float)? {
        guard !xs.isEmpty else { return nil }
        let m = xs.reduce(0, +) / Float(xs.count)
        let v = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(xs.count)
        return (m, sqrt(v))
    }

    /// 最小二乘斜率
    private func slope(_ xs: [Float], _ ys: [Float]) -> Float {
        guard xs.count == ys.count, xs.count > 1 else { return 0 }
        let mx = xs.reduce(0, +) / Float(xs.count)
        let my = ys.reduce(0, +) / Float(ys.count)
        var num: Float = 0, den: Float = 0
        for i in xs.indices {
            let dx = xs[i] - mx
            num += dx * (ys[i] - my)
            den += dx * dx
        }
        return den > 0 ? num / den : 0
    }

    /// 线性插值重采样到指定点数
    private func resample(_ xs: [Float], to n: Int) -> [Float] {
        guard xs.count >= 2, n >= 2 else { return xs }
        return (0..<n).map { k in
            let pos = Float(k) / Float(n - 1) * Float(xs.count - 1)
            let i = min(Int(pos), xs.count - 2)
            return xs[i] + (xs[i + 1] - xs[i]) * (pos - Float(i))
        }
    }

    // MARK: - 合成母语者参照 F0

    /// 合成目标词并提取归一化 F0；有声帧过少或走向与目标声调矛盾时返回 []（让调用方回退）。
    /// - Parameter tones: 目标声调序列，用于去除 TTS 句调下倾并校验可信度。
    ///   关卡 2 来自语料库，关卡 3 来自 `PinyinConverter`——两处都拿得到，
    ///   因此本矫正对任意文本都适用（自由文本无法预录真人音，只能靠 TTS）。
    func synthesizeReferenceF0(for text: String, tones: [Int] = []) async -> [Float] {
        let samples = await render16k(text)
        guard samples.count >= 512 else {
            #if DEBUG
            print("[SpeechService] TTS 合成失败 (samples=\(samples.count)) '\(text)' → 回退几何轮廓")
            #endif
            return []
        }
        // clean：TTS 提取的参照同样有八度错误/尖峰，先清理再归一化
        return f0Track(from: samples, tag: "TTS '\(text)'", tones: tones)
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
