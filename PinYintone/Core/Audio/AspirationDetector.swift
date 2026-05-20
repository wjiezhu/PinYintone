import Accelerate
import Foundation

/// 送气检测（“吹散蒲公英”模块）：动态底噪基线 + 15 dB 阈值。
/// 参数遵循 CLAUDE.md：
/// - 判定阈值：底噪 + 15 dB（启动后前 500 ms 采集底噪）
/// - 触发率通关线：≥ 0.6（600 ms 窗口内触发帧占比）
final class AspirationDetector {

    /// 阈值高于底噪的 dB 增量（CLAUDE.md：+15 dB）
    private let thresholdOffsetDB: Float = 15

    /// 当前底噪基线（dB）；由 calibrateBaseline 写入
    private(set) var baselineDB: Float = -.infinity

    /// 触发阈值（dB）= 底噪 + 15 dB
    var thresholdDB: Float { baselineDB + thresholdOffsetDB }

    /// 送入前 500 ms 的静音帧以校准底噪基线
    func calibrateBaseline(frames: [[Float]]) {
        let all = frames.flatMap { $0 }
        guard !all.isEmpty else { return }
        baselineDB = decibels(of: all)
    }

    /// 判断单帧是否触发送气（能量 > 底噪 + 15 dB）
    func detect(frame: [Float]) -> Bool {
        guard frame.isEmpty == false else { return false }
        return decibels(of: frame) > thresholdDB
    }

    /// 计算一段帧序列的触发率（触发帧占比，0–1）
    func triggerRate(frames: [[Float]]) -> Float {
        guard !frames.isEmpty else { return 0 }
        let hits = frames.reduce(0) { $0 + (detect(frame: $1) ? 1 : 0) }
        return Float(hits) / Float(frames.count)
    }

    // MARK: - 私有

    /// 帧的 RMS 能量转分贝；下限钳制避免 log(0)
    private func decibels(of samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return 20 * log10(max(rms, 1e-7))
    }
}
