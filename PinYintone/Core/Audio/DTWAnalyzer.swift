import Foundation

// 归一化 DTW，欧氏距离（L2），作用于 z-score 归一化后的 F0 序列
// 通关线：归一化 DTW ≤ 0.5（见 CLAUDE.md）
final class DTWAnalyzer {

    /// 计算两条 F0 序列的归一化 DTW 距离
    func distance(reference: [Float], candidate: [Float]) -> Float {
        fatalError("TODO: 实现 — 构建代价矩阵 → 动态规划 → 路径归一化")
    }

    /// 根据 DTW 距离返回评分等级
    func grade(dtwScore: Float) -> FeedbackGrade {
        fatalError("TODO: 实现 — excellent/good/needsPractice/fail 分档")
    }
}
