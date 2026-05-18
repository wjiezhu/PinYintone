import Accelerate
import Foundation

// YIN 算法实现
// 检测范围：75 Hz – 500 Hz（见 CLAUDE.md）
// YIN 阈值：0.15
// 无声帧返回 0.0
final class F0Extractor {

    /// 从单帧（512 samples，16kHz）提取基频（Hz）；无声帧返回 0.0
    func extract(frame: [Float]) -> Float {
        fatalError("TODO: 实现 — YIN 差分函数 → 累积均值归一化 → 阈值判断 → 抛物线插值")
    }

    /// z-score 归一化整条 F0 轨迹（per utterance，忽略 0 值帧）
    func normalize(_ track: [Float]) -> [Float] {
        fatalError("TODO: 实现")
    }
}
