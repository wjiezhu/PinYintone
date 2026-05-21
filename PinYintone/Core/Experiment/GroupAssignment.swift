import Foundation

enum ExperimentGroup: String, Codable {
    case staticColor  // 模式 A：静态色块反馈
    case dynamicF0    // 模式 B：动态 F0 波形反馈
}

/// A/B 分组：由班级码（测试码）前缀决定，研究者通过发不同前缀的码控制分组。
/// 作用域仅限关卡 2（声调训练），关卡 3 不参与分流。
///
/// 规则（客户端本地判定，离线可用）：
/// - `1` 开头 → 组 A（staticColor）
/// - `2` 开头 → 组 B（dynamicF0）
/// - 其余前缀 / 游客（无码）→ 组 B（dynamicF0）
enum GroupAssignment {
    static func group(forClassCode code: String?) -> ExperimentGroup {
        guard let first = code?.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return .dynamicF0   // 游客（无码）默认 B
        }
        switch first {
        case "1": return .staticColor
        case "2": return .dynamicF0
        default:  return .dynamicF0
        }
    }
}
