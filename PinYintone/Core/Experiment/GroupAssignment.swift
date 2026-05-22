import Foundation

enum ExperimentGroup: String, Codable {
    case staticColor  // 模式 A：静态色块反馈
    case dynamicF0    // 模式 B：动态 F0 波形反馈
}

/// A/B 分组：注册时由**后端均衡随机分配**（哪组人少进哪组），结果存 profile.experimentGroup。
/// 作用域仅限关卡 2（声调训练），关卡 3 不参与分流。
/// 离线无法联系后端时，用本地随机兜底。
enum GroupAssignment {
    /// 离线兜底：本地 50/50 随机
    static func randomGroup() -> ExperimentGroup {
        Bool.random() ? .staticColor : .dynamicF0
    }
}
