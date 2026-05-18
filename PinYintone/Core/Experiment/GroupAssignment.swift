import Foundation

enum ExperimentGroup: String, Codable {
    case staticColor  // 模式 A：静态色块反馈
    case dynamicF0    // 模式 B：动态 F0 波形反馈
}

/// A/B 分组单例：安装时随机一次，UserDefaults 持久化，不可更改。
/// 作用域仅限关卡 2（声调训练），关卡 3 不参与分流。
final class GroupAssignment {
    static let shared = GroupAssignment()

    private static let key = "pt_experiment_group"

    private(set) var group: ExperimentGroup

    private init() {
        if let saved = UserDefaults.standard.string(forKey: Self.key),
           let g = ExperimentGroup(rawValue: saved) {
            group = g
        } else {
            group = Bool.random() ? .staticColor : .dynamicF0
            UserDefaults.standard.set(group.rawValue, forKey: Self.key)
        }
    }
}
