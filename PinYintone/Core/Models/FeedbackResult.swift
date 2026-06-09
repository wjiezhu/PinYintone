import Foundation

enum FeedbackGrade: String, Codable {
    case excellent      // DTW ≤ 0.2
    case good           // DTW 0.2–0.35
    case needsPractice  // DTW 0.35–0.5
    case fail           // DTW > 0.5
}

/// 按字方向诊断：当某音节 DTW 偏高时，给出"应该往哪唱"的箭头提示。
/// 与 A/B 实验无关，A、B 两组录完都共享同一份事后反馈。
enum DirectionHint: String, Codable {
    case ok                  // 这个字唱对了，不显示箭头
    case shouldStayHigh      // T1：保持高平，不要起伏
    case shouldRise          // T2：应该往上唱
    case shouldDipThenRise   // T3：先降后升
    case shouldFall          // T4：应该往下唱
    case neutral             // T5 轻声 或 无法判定

    /// 用于 UI 显示的 SF Symbol 名。
    var symbol: String {
        switch self {
        case .ok:                 return "checkmark.circle.fill"
        case .shouldStayHigh:     return "arrow.right"
        case .shouldRise:         return "arrow.up.right"
        case .shouldDipThenRise:  return "arrow.down.right.and.arrow.up.right"
        case .shouldFall:         return "arrow.down.right"
        case .neutral:            return "questionmark.circle"
        }
    }

    /// 本地化键。
    var localizationKey: String {
        switch self {
        case .ok:                 return "direction_ok"
        case .shouldStayHigh:     return "direction_should_stay_high"
        case .shouldRise:         return "direction_should_rise"
        case .shouldDipThenRise:  return "direction_should_dip_then_rise"
        case .shouldFall:         return "direction_should_fall"
        case .neutral:            return "direction_neutral"
        }
    }
}

/// 单个音节的诊断结果（按字反馈）。
struct ToneSegmentResult: Codable, Identifiable {
    var id: Int { syllableIndex }
    let syllableIndex: Int       // 0-based
    let hanziChar: String        // 显示用，如 "跑"
    let expectedTone: Int        // 1–5
    let segmentScore: Float      // 该段归一化 DTW；越低越好
    let directionHint: DirectionHint

    /// 单字是否通关（同总分阈值 0.5）。
    var passed: Bool { segmentScore <= 0.5 }
}

struct FeedbackResult {
    let dtwScore: Float
    let grade: FeedbackGrade
    let attemptNumber: Int
    let segments: [ToneSegmentResult]  // 按字诊断；按音节顺序

    /// 错误字下标（向后兼容旧字段，从 segments 推导）。
    var toneErrors: [Int] {
        segments.filter { !$0.passed }.map { $0.syllableIndex }
    }

    /// 面向用户的百分制得分（0–100，越高越好）。
    /// 由归一化 DTW（越低越好）分段线性映射，与四级阈值对齐；60 分 = 通关线（DTW 0.5）。
    /// 优秀 90–100 · 良好 75–90 · 继续练习 60–75 · 再试 <60。
    var score: Int {
        let d = max(0, dtwScore)
        let p: Float
        switch d {
        case ..<0.2:  p = 100 - (d / 0.2) * 10
        case ..<0.35: p = 90 - ((d - 0.2) / 0.15) * 15
        case ..<0.5:  p = 75 - ((d - 0.35) / 0.15) * 15
        default:      p = max(0, 60 - ((d - 0.5) / 0.5) * 60)
        }
        return Int(p.rounded())
    }
}
