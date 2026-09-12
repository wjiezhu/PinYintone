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
    /// 全平调词整体掉调——走向闸门判定，不归咎于某个字
    case wordDropping

    /// 用于 UI 显示的 SF Symbol 名。
    var symbol: String {
        switch self {
        case .ok:                 return "checkmark.circle.fill"
        case .shouldStayHigh:     return "arrow.right"
        case .shouldRise:         return "arrow.up.right"
        case .shouldDipThenRise:  return "arrow.down.right.and.arrow.up.right"
        case .shouldFall:         return "arrow.down.right"
        case .neutral:            return "questionmark.circle"
        case .wordDropping:       return "arrow.down.forward"
        }
    }

    /// 教练卡的完整句式模板键（比 `localizationKey` 的短标签多一层"怎么做"）。
    var coachKey: String {
        switch self {
        case .ok:                 return "coach_all_good"
        case .shouldStayHigh:     return "coach_stay_high"
        case .shouldRise:         return "coach_rise"
        case .shouldDipThenRise:  return "coach_dip_then_rise"
        case .shouldFall:         return "coach_fall"
        case .neutral:            return "coach_neutral"
        case .wordDropping:       return "coach_keep_level"   // 整词句式，无 %@ 占位符
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
        case .wordDropping:       return "direction_word_dropping"
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

/// 教练卡的内容：一条主提示 + 可选的一句鼓励。
///
/// 刻意只留一个 `focusChar`——档案 §4.3 要求每次最多突出一个调整方向，
/// 用类型把"想给两条"这件事挡在编译期之外。
struct CoachAdvice {
    /// 这次要改的那个字；全对时为 nil（此时 `hint == .ok`，模板不含占位符）
    let focusChar: String?
    let hint: DirectionHint
    /// 已经念稳了的另一个字，用来先肯定再纠正；没有则为 nil
    let praiseChar: String?
}

struct FeedbackResult {
    let dtwScore: Float
    /// 是否被平调词走向闸门拦下（全一声的词整体掉调）。
    /// 此时 `grade` 恒为 `.fail`，即便 `dtwScore` 还在通关线内。
    var levelToneDropped: Bool = false
    let grade: FeedbackGrade
    let attemptNumber: Int
    let segments: [ToneSegmentResult]  // 按字诊断；按音节顺序

    /// 错误字下标（向后兼容旧字段，从 segments 推导）。
    var toneErrors: [Int] {
        segments.filter { !$0.passed }.map { $0.syllableIndex }
    }

    /// 挑出**唯一**一条要给学习者的行动提示。
    ///
    /// 选取规则：在所有"没唱对"的音节里取分段 DTW 最差的那个——
    /// 差得最多的地方改起来收益最大。全部唱对时返回 `.ok`（鼓励文案）。
    var coachAdvice: CoachAdvice {
        // 闸门触发时逐字 DTW 可能都在通关线内，逐字诊断会得出"全对"，
        // 与 grade = .fail 直接矛盾。整词掉调是此刻唯一该说的事（§4.3 只给一个方向）。
        if levelToneDropped {
            return CoachAdvice(focusChar: nil, hint: .wordDropping, praiseChar: nil)
        }
        let needsWork = segments.filter { $0.directionHint != .ok }
        guard let worst = needsWork.max(by: { $0.segmentScore < $1.segmentScore }) else {
            return CoachAdvice(focusChar: nil, hint: .ok, praiseChar: nil)
        }
        // 只有在"另一个字确实稳了"时才夸，避免全错还说"很稳"
        let praise = segments.first {
            $0.syllableIndex != worst.syllableIndex && $0.passed
        }
        return CoachAdvice(focusChar: worst.hanziChar,
                           hint: worst.directionHint,
                           praiseChar: praise?.hanziChar)
    }

    /// 面向用户的百分制得分（0–100，越高越好）。
    /// 由归一化 DTW（越低越好）分段线性映射，与四级阈值对齐；60 分 = 通关线（DTW 0.5）。
    /// 优秀 90–100 · 良好 75–90 · 继续练习 60–75 · 再试 <60。
    var score: Int {
        // 被闸门拦下就是不通关，分数不得高于通关线对应的 60 分，
        // 否则会出现"85 分但不通关"。
        if levelToneDropped { return min(59, Self.mapped(dtwScore)) }
        return Self.mapped(dtwScore)
    }

    private static func mapped(_ dtwScore: Float) -> Int {
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
