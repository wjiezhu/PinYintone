import AVFoundation
import CryptoKit
import Foundation

/// 待上传的录音（现场实测改版，2026-10-28）。
///
/// **只有三项同时成立才会入队**：
/// 1. 这次尝试属于现场实测（前测、训练、后测）。普通练习与自测的录音一律不留。
/// 2. 参与者纳入所用的配置接收录音（`audio_upload`）。
/// 3. 参与者同意的那一版文本写明了上传录音（consent-2.0）。只同意过旧文本的人不收。
///
/// 录音先在本机压成 AAC（ADTS 裸流，16 kHz 单声道，系统自带的编码器），一个词约 5–10 KB。
/// 不用 m4a 容器：AVAudioFile 写 m4a 会在文件头预留约 24 KB 空白，比声音本身大几倍。
/// 存在本账号自己的目录里，上传成功或被服务端明确拒收后立即删除。
/// 退出研究、删除账号时整个目录删掉。取消的那一次不留声音。
///
/// 上传顺序排在尝试记录之后：录音挂在尝试上，服务端要先有那条尝试。
@MainActor
final class ResearchRecordingQueue {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = ResearchRecordingQueue()

    nonisolated struct Item: Codable, Equatable {
        let attemptID: UUID
        let fileName: String
        let durationMs: Int
        let sha256: String
        let byteSize: Int
    }

    nonisolated static let audioFormat = "aac_adts"
    nonisolated static let sampleRate = 16_000

    private static let queueName = "recordings"
    private(set) var pending: [Item] = []

    private init() {}

    /// 这位参与者现在的录音该不该留：配置收录音，且他同意的文本写明了录音
    static func shouldCapture() -> Bool { shouldCapture(state: ResearchStore.shared.state) }

    nonisolated static func shouldCapture(state: ResearchState) -> Bool {
        state.audioUpload == true
            && ResearchConsent.allowsAudioUpload(consentVersion: state.consentVersion)
    }

    func reload() {
        pending = ResearchStore.shared.loadQueue(Self.queueName)
        // 文件被系统清掉了的条目没法再传，出队
        let missing = pending.filter { !FileManager.default.fileExists(atPath: url(for: $0).path) }
        if !missing.isEmpty { remove(Set(missing.map(\.attemptID))) }
    }

    /// 压缩并入队。在后台编码，主线程只登记结果。
    func enqueue(pcm: [Int16], attemptID: UUID) {
        guard Self.shouldCapture(), ResearchGate.shouldCollect(),
              !pcm.isEmpty, let dir = directory() else { return }
        let account = ResearchStore.shared.accountKey
        let fileName = "\(attemptID.uuidString).aac"
        let fileURL = dir.appendingPathComponent(fileName)
        Task.detached(priority: .utility) {
            guard let data = try? Self.encodeAAC(pcm: pcm, to: fileURL) else {
                try? FileManager.default.removeItem(at: fileURL)
                return
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let item = Item(attemptID: attemptID, fileName: fileName,
                            durationMs: pcm.count * 1000 / Self.sampleRate,
                            sha256: digest, byteSize: data.count)
            await MainActor.run {
                let q = ResearchRecordingQueue.shared
                // 编码期间换了账号或退出了研究：这段录音不属于现在的状态，删掉
                guard ResearchStore.shared.accountKey == account,
                      ResearchRecordingQueue.shouldCapture() else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }
                q.pending.append(item)
                q.persist()
                ResearchUploader.shared.scheduleFlushSoon()
            }
        }
    }

    func data(for item: Item) -> Data? { try? Data(contentsOf: url(for: item)) }

    /// 已上传或被明确拒收：出队并删文件
    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for item in pending where ids.contains(item.attemptID) {
            try? FileManager.default.removeItem(at: url(for: item))
        }
        pending.removeAll { ids.contains($0.attemptID) }
        persist()
    }

    /// 退出研究、删除账号：本账号的录音全部删掉
    func removeAll() {
        pending.removeAll()
        persist()
        if let dir = directory(create: false) { try? FileManager.default.removeItem(at: dir) }
    }

    private func persist() { ResearchStore.shared.saveQueue(Self.queueName, pending) }

    private func url(for item: Item) -> URL {
        (directory(create: false) ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(item.fileName)
    }

    /// 按账号分目录；目录名用存储域名（账号标识的摘要），不含 Apple 标识本身。
    /// 放在 Application Support 并排除 iCloud 备份：录音不该随备份离开这台手机。
    private func directory(create: Bool = true) -> URL? {
        guard let domain = ResearchStore.shared.storageDomain,
              let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        var dir = base.appendingPathComponent("ResearchAudio", isDirectory: true)
            .appendingPathComponent(domain, isDirectory: true)
        if create, !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
        }
        return dir
    }

    /// 16 kHz 单声道 Int16 PCM → AAC（ADTS）。只用系统的 AVFoundation，不引第三方库。
    /// 文件类型由扩展名决定：`url` 须以 `.aac` 结尾。
    nonisolated static func encodeAAC(pcm: [Int16], to url: URL) throws -> Data {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(sampleRate),
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(pcm.count)),
              let channel = buffer.floatChannelData?[0] else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (i, s) in pcm.enumerated() { channel[i] = Float(s) / 32768 }
        buffer.frameLength = AVAudioFrameCount(pcm.count)
        try? FileManager.default.removeItem(at: url)
        do {
            // 文件在这个作用域结束时关闭，写入才完整
            let file = try AVAudioFile(forWriting: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: Double(sampleRate),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        return try Data(contentsOf: url)
    }
}
