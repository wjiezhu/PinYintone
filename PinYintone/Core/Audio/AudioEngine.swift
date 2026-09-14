import AVFoundation
import Foundation

/// 录音引擎：使用 AVAudioEngine 采集麦克风音频，并实时转换为
/// **16 kHz / 16-bit / 单声道** 的 PCM 数据。
///
/// - 采样率固定 16 000 Hz（CLAUDE.md 锁定，不可更改）
/// - 每累积 1600 个采样（= 0.1 s）回调一次 `onChunk`
/// - 可设定录音时长，到时自动结束并回调 `onFinish`
/// - 录音结束（手动 `stop()` 或到时）返回完整 PCM
///
/// 线程模型：
/// - `onChunk` 在内部处理队列执行（非主线程）；消费方如需更新 UI 请自行切回主线程
/// - `onFinish` 统一在主线程执行
/// - `isRecording` / `currentTime` 为线程安全的只读属性
final class AudioEngine {

    enum AudioEngineError: Error {
        case converterUnavailable      // 无法创建 AVAudioConverter
        case engineStartFailed(Error)  // AVAudioEngine 启动失败
        case invalidInputFormat        // 输入格式无效（模拟器无麦克风 / 权限被拒 / 会话被占用）
    }

    // MARK: - 固定参数（不可更改）

    /// 采样率：16 kHz（CLAUDE.md 锁定）
    let sampleRate: Double = 16_000
    /// 每次回调的采样数：1600 = 0.1 s @ 16 kHz
    let chunkSize: Int = 1600

    // MARK: - 回调

    /// 每累积 1600 个采样回调一次（16-bit PCM 分片）。在处理队列执行。
    var onChunk: (([Int16]) -> Void)?
    /// 录音结束后回调，返回完整 PCM。在主线程执行。
    var onFinish: (([Int16]) -> Void)?

    // MARK: - 状态（线程安全只读）

    /// 是否正在录音
    var isRecording: Bool { lock.withLock { _isRecording } }
    /// 当前已录制时长（秒）
    var currentTime: TimeInterval { lock.withLock { Double(_totalSamples) / sampleRate } }

    // MARK: - 内部属性

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    /// 当前 converter 是按哪个输入格式建的；格式变化时据此重建
    private var converterSourceFormat: AVAudioFormat?

    /// 目标格式：16-bit 整型、16 kHz、单声道、交错
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    /// 处理队列：把音频线程产出的采样搬到这里做累积与分片，避免阻塞实时线程
    private let processingQueue = DispatchQueue(label: "com.pinyintone.audioengine.processing")

    /// 保护下列可变状态
    private let lock = NSLock()
    private var _isRecording = false
    private var _totalSamples = 0
    private var maxSamples: Int?         // 设定时长对应的采样上限；nil = 不限时
    private var pcmBuffer: [Int16] = []  // 完整录音累积
    private var pending: [Int16] = []    // 未满 1600 的暂存分片

    // MARK: - 控制

    /// 开始录音。
    /// - Parameter duration: 录音时长（秒）；传 nil 表示不限时，需手动 `stop()`。
    func start(duration: TimeInterval? = nil) throws {
        guard !isRecording else { return }

        // 0) 先配置音频会话，**再**碰 inputNode。顺序不能反：
        // 访问 `engine.inputNode` 会按**当时**的会话类别实例化 IO unit 并缓存其格式。
        // 若此刻会话还停在 .playback（刚听完 TTS 示范或回听就是这种状态），
        // 拿到的是 0 Hz 的无效格式且会被缓存，后面的格式校验必然失败，
        // 表现为「听完示范再录音就起不来」。
        //
        // measurement 模式关闭额外处理，保证电平/基频分析准确。
        //
        // 这里**不设** setPreferredSampleRate(16000)：CLAUDE.md 锁定的 16 kHz 是
        // 分析链路（targetFormat → YIN/DTW）的采样率，不是麦克风采集率。
        // 真机上请求 16 kHz 会让硬件真的切到 16 kHz，而 inputNode 缓存的格式仍是
        // 48 kHz，装 tap 时两者不一致 → AVAudioEngine 初始化失败（error -10868），
        // 表现为"按录音没反应"。让硬件跑原生采样率，由下面的 converter 降到 16 kHz。
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // 1) 防御性清理：即便逻辑上没在录音，也可能残留 tap / 引擎仍在跑
        // （前次录音被电话/Siri/后台切换打断、teardown 未跑完等情形）。
        // 在已装 tap 的 AVAudioNode 上再装 tap 会抛 NSException → 直接闪退。
        // 必须无条件先 removeTap + stop engine 一次。
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        // 2) 校验输入格式是否可用（converter 改为按 tap 实际交付的格式懒建，见 convert）
        let hwFormat = input.outputFormat(forBus: 0)
        // 模拟器无麦克风 / 麦克风权限被拒 / 会话被占用时，inputNode 可能返回 sampleRate
        // 或 channelCount 为 0 的无效格式；直接传给 installTap 会抛
        // IsFormatSampleRateAndChannelCountValid 异常导致进程崩溃。先校验，优雅失败。
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw AudioEngineError.invalidInputFormat
        }
        // 3) 复位状态
        lock.withLock {
            _isRecording = true
            _totalSamples = 0
            pcmBuffer.removeAll(keepingCapacity: true)
            pending.removeAll(keepingCapacity: true)
            maxSamples = duration.map { Int($0 * sampleRate) }
        }

        // 4) 安装 tap：format 传 nil，让引擎用节点**当时**的真实格式，
        // 而不是上面那个可能已经过期的 hwFormat 快照（耳机插拔、来电打断后的
        // 路由切换都会让缓存格式失效）。转换器按第一个 buffer 的格式懒建。
        input.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self, let samples = self.convert(buffer) else { return }
            self.processingQueue.async { self.accumulate(samples) }
        }

        // 5) 启动引擎
        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            lock.withLock { _isRecording = false }
            throw AudioEngineError.engineStartFailed(error)
        }
    }

    /// 手动停止录音并返回完整 PCM（亦会触发 `onFinish`）。
    @discardableResult
    func stop() -> [Int16] {
        let wasRecording = lock.withLock { _isRecording }
        guard wasRecording else {
            return lock.withLock { pcmBuffer }
        }
        teardown()
        let buffer = lock.withLock { () -> [Int16] in
            _isRecording = false
            return pcmBuffer
        }
        DispatchQueue.main.async { [weak self] in self?.onFinish?(buffer) }
        return buffer
    }

    // MARK: - 工具

    /// 将 16-bit PCM 归一化为 [-1, 1] 的 Float，供 F0Extractor / AspirationDetector 等 DSP 使用。
    static func floatSamples(from pcm: [Int16]) -> [Float] {
        pcm.map { Float($0) / 32768.0 }
    }

    // MARK: - 私有实现

    /// 在音频线程同步将硬件缓冲转换为目标格式的 Int16 采样数组。
    private func convert(_ inputBuffer: AVAudioPCMBuffer) -> [Int16]? {
        // tap 实际交付的格式才是权威值：首个 buffer 到达时建转换器；
        // 若中途格式变了（路由切换）就按新格式重建，而不是拿旧的硬转。
        if converter == nil || converterSourceFormat != inputBuffer.format {
            converter = AVAudioConverter(from: inputBuffer.format, to: targetFormat)
            converterSourceFormat = converter == nil ? nil : inputBuffer.format
        }
        guard let converter else { return nil }

        // 按采样率比估算输出容量（多留 1 帧余量）
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var convError: NSError?
        let status = converter.convert(to: outBuffer, error: &convError) { _, inputStatus in
            if consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error,
              outBuffer.frameLength > 0,
              let channel = outBuffer.int16ChannelData else { return nil }

        return Array(UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
    }

    /// 在处理队列累积采样、切出满 1600 的分片，并在到时后结束。
    private func accumulate(_ samples: [Int16]) {
        var chunks: [[Int16]] = []
        var finished = false
        var finalBuffer: [Int16] = []

        lock.withLock {
            guard _isRecording else { return }

            pcmBuffer.append(contentsOf: samples)
            pending.append(contentsOf: samples)
            _totalSamples += samples.count

            // 切出所有满 1600 的分片
            while pending.count >= chunkSize {
                chunks.append(Array(pending.prefix(chunkSize)))
                pending.removeFirst(chunkSize)
            }

            // 到达设定时长 → 裁剪到精确长度并结束
            if let maxSamples, _totalSamples >= maxSamples {
                if pcmBuffer.count > maxSamples {
                    pcmBuffer = Array(pcmBuffer.prefix(maxSamples))
                }
                finalBuffer = pcmBuffer
                finished = true
                _isRecording = false
            }
        }

        for chunk in chunks { onChunk?(chunk) }

        if finished {
            DispatchQueue.main.async { [weak self] in
                self?.teardown()
                self?.onFinish?(finalBuffer)
            }
        }
    }

    /// 移除 tap、停止引擎、关闭会话。
    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        converter = nil
        converterSourceFormat = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
