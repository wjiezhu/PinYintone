import Foundation

enum FeedbackGrade: String, Codable {
    case excellent      // DTW ≤ 0.2
    case good           // DTW 0.2–0.35
    case needsPractice  // DTW 0.35–0.5
    case fail           // DTW > 0.5
}

struct FeedbackResult {
    let dtwScore: Float
    let grade: FeedbackGrade
    let attemptNumber: Int
    let toneErrors: [Int]  // 发音错误的音节下标

    /// 面向用户的百分制得分（0–100，越高越好）。
    /// 由归一化 DTW（越低越好）分段线性映射，与四级阈值对齐；60 分 = 通关线（DTW 0.5）。
    /// 优秀 90–100 · 良好 75–90 · 继续练习 60–75 · 再试 <60。
    var score: Int {
        let d = max(0, dtwScore)
        let p: Float
        switch d {
        case ..<0.2:  p = 100 - (d / 0.2) * 10               // 0→100, 0.2→90
        case ..<0.35: p = 90 - ((d - 0.2) / 0.15) * 15       // 0.2→90, 0.35→75
        case ..<0.5:  p = 75 - ((d - 0.35) / 0.15) * 15      // 0.35→75, 0.5→60
        default:      p = max(0, 60 - ((d - 0.5) / 0.5) * 60) // 0.5→60, 1.0→0
        }
        return Int(p.rounded())
    }
}
