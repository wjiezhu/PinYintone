import Foundation

/// 关卡 2 词集划分。
///
/// 语料切成**训练池**和一个与训练不重叠的**固定测试词集**：
/// 前测与后测用同一份测试词集，保证增益比较不被"练过的词"污染。
///
/// 历史说明：`set1` / `set2` 原本是为 A/B 受试内设计切出的两个难度相当的词集
/// （反馈条件绑定词集）。取消 A/B 后两者合并为单一训练池，标签仅保留在语料与
/// 历史记录里，不再影响出题顺序或反馈呈现。
nonisolated enum WordSet: String, Codable, CaseIterable {
    case set1
    case set2
    case assessment

    /// 训练池所含的词集标签（合并遍历，不再分块）
    static var trainingSets: [WordSet] { [.set1, .set2] }

    /// 是否为前测/后测的固定测试词集
    var isAssessment: Bool { self == .assessment }
}

nonisolated enum AssessmentSet {
    /// 测试词集版本号，随每条记录上报。
    /// **改动测试词集内容必须同时递增该版本号**，否则跨版本的前后测数据不可比。
    static let version = "assess-v1"
}
