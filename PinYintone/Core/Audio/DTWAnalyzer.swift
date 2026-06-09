import Foundation

/// 归一化动态时间规整（路径长度归一化 DTW，参考 Richter & Guðnason 2023）
/// 参数遵循 CLAUDE.md：
/// - 距离度量：欧氏距离（L2）；对标量 F0 序列即 |Δ|
/// - 作用于 z-score 归一化后的 F0 序列，忽略 0 值（无声）帧
/// - 通关线：归一化 DTW ≤ 0.5
final class DTWAnalyzer {

    /// 计算两条 F0 序列的归一化 DTW 距离（值域 ≥ 0，越小越接近）
    /// - Parameters:
    ///   - reference: 母语者归一化 F0 轨迹
    ///   - candidate: 学习者归一化 F0 轨迹
    func distance(reference: [Float], candidate: [Float]) -> Float {
        // CLAUDE.md：DTW 对齐时忽略 0 帧（无声帧）
        let a = reference.filter { $0 != 0 }
        let b = candidate.filter { $0 != 0 }
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return .infinity }

        // dp[i][j] = 到达 (i,j) 的最小累积代价
        var dp = [[Float]](repeating: [Float](repeating: .infinity, count: n + 1), count: m + 1)
        // prev：1=上方, 2=左方, 3=对角（用于回溯路径长度）
        var prev = [[UInt8]](repeating: [UInt8](repeating: 0, count: n + 1), count: m + 1)
        dp[0][0] = 0

        for i in 1...m {
            for j in 1...n {
                let cost = abs(a[i - 1] - b[j - 1])   // 标量序列：欧氏(L2) = |Δ|
                let up = dp[i - 1][j]
                let left = dp[i][j - 1]
                let diag = dp[i - 1][j - 1]
                let best = min(diag, min(up, left))
                dp[i][j] = cost + best
                prev[i][j] = (best == diag) ? 3 : (best == up ? 1 : 2)
            }
        }

        // 路径长度归一化：D_norm = D_dtw / W（W = 最优路径步数）
        let pathLen = tracePathLength(prev, m: m, n: n)
        return dp[m][n] / Float(max(pathLen, 1))
    }

    /// 根据归一化 DTW 距离返回评分等级（CLAUDE.md 通关线 ≤ 0.5）
    func grade(dtwScore: Float) -> FeedbackGrade {
        switch dtwScore {
        case ..<0.2:  return .excellent
        case ..<0.35: return .good
        case ...0.5:  return .needsPractice   // 0.35–0.5（含 0.5）仍算通关
        default:      return .fail            // >0.5 不通关
        }
    }

    /// 是否通关（归一化 DTW ≤ 0.5）
    func passed(_ dtwScore: Float) -> Bool { dtwScore <= 0.5 }

    /// 把参照与候选序列各等分为 nSegments 段，对每段独立计算归一化 DTW。
    /// 用于按字粒度反馈：每个汉字一段。
    ///
    /// **限制**：对 `ToneContour.ideal()` 生成的参照精确分段（每音节固定帧数）；
    /// 对 TTS 合成的参照只能近似等分，因为不同音节实际时长不同。
    /// 学生 F0 同理按等分切——足够给"哪个字偏差大"的提示，但不是音段级精确切分。
    ///
    /// - Returns: 长度 = nSegments；某段任意一侧无有效帧则该段返回 `.infinity`。
    func segmentScores(reference: [Float], candidate: [Float], nSegments: Int) -> [Float] {
        guard nSegments > 0 else { return [] }
        let a = reference.filter { $0 != 0 }
        let b = candidate.filter { $0 != 0 }
        guard !a.isEmpty, !b.isEmpty else {
            return Array(repeating: .infinity, count: nSegments)
        }

        var scores: [Float] = []
        scores.reserveCapacity(nSegments)
        for i in 0..<nSegments {
            let aStart = (a.count * i) / nSegments
            let aEnd   = (a.count * (i + 1)) / nSegments
            let bStart = (b.count * i) / nSegments
            let bEnd   = (b.count * (i + 1)) / nSegments
            let aSeg = Array(a[aStart..<aEnd])
            let bSeg = Array(b[bStart..<bEnd])
            if aSeg.isEmpty || bSeg.isEmpty {
                scores.append(.infinity)
            } else {
                scores.append(distance(reference: aSeg, candidate: bSeg))
            }
        }
        return scores
    }

    // MARK: - 私有

    private func tracePathLength(_ prev: [[UInt8]], m: Int, n: Int) -> Int {
        var i = m, j = n, steps = 0
        while i > 0 || j > 0 {
            steps += 1
            guard i > 0, j > 0 else {
                if i > 0 { i -= 1 } else { j -= 1 }
                continue
            }
            switch prev[i][j] {
            case 1:  i -= 1            // 上方
            case 2:  j -= 1            // 左方
            default: i -= 1; j -= 1    // 对角
            }
        }
        return steps
    }
}
