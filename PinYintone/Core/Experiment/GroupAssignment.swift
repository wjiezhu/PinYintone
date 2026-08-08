import Foundation

enum ExperimentGroup: String, Codable {
    case staticColor  // 模式 A：静态色块反馈
    case dynamicF0    // 模式 B：动态 F0 波形反馈
}

/// A/B 分配（**受试内设计**）。
///
/// `profile.experimentGroup` 不再表示"这个人用哪种反馈"，而是该被试的
/// **平衡顺序（counterbalance order）**——决定训练词 A 子集、B 子集分别用哪种呈现，
/// 以在被试间抵消词集本身的难度差异：
/// - `.staticColor` 顺序：训练 A 子集用静态色块，B 子集用动态曲线；
/// - `.dynamicF0`   顺序：训练 A 子集用动态曲线，B 子集用静态色块。
///
/// 呈现方式随每条记录以 `group_assignment` 上报（按词标注）。前后测为裸测，无 A/B 呈现。
/// 注册时后端仍均衡随机分配该顺序（沿用旧字段），离线本地随机兜底。
enum GroupAssignment {
    /// 离线兜底：本地 50/50 随机（此处即随机平衡顺序）
    static func randomGroup() -> ExperimentGroup {
        Bool.random() ? .staticColor : .dynamicF0
    }

    /// 由"词的子集 + 被试平衡顺序"推出该词的呈现方式。
    /// - test / nil（前后测词或送气词）：无 A/B 呈现，返回 nil。
    static func presentationMode(subset: LexemeSubset?,
                                 order: ExperimentGroup) -> ExperimentGroup? {
        switch subset {
        case .trainingA:
            return order == .staticColor ? .staticColor : .dynamicF0
        case .trainingB:
            return order == .staticColor ? .dynamicF0 : .staticColor
        case .test, .none:
            return nil
        }
    }
}
