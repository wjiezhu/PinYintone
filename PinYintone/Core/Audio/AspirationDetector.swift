import Accelerate
import Foundation

// 送气检测：动态底噪基线 + 15 dB 阈值
// 通关线：触发率 ≥ 0.6（600 ms 窗口，见 CLAUDE.md）
final class AspirationDetector {

    /// 当前底噪基线（dB）；由 calibrateBaseline 写入
    private(set) var baselineDB: Float = 0

    /// 送入前 500 ms 的静音帧以校准底噪基线
    func calibrateBaseline(frames: [[Float]]) {
        fatalError("TODO: 实现 — 计算 RMS → 转 dB → 存 baselineDB")
    }

    /// 判断单帧是否触发送气（能量 > baselineDB + 15）
    func detect(frame: [Float]) -> Bool {
        fatalError("TODO: 实现")
    }

    /// 计算一段帧序列的触发率
    func triggerRate(frames: [[Float]]) -> Float {
        fatalError("TODO: 实现")
    }
}
