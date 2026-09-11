import Foundation

/// 研究阶段（升级需求 §3.1）。三阶段共用同一套算法与阈值，只有**反馈呈现**不同。
///
/// - `pretest` / `posttest`：裸测。录完不显示分数、等级、颜色或曲线，
///   后台照常记录结果与质量字段，用于建立基线并与后测比较。
/// - `training`：显示静态颜色或动态 F0 曲线 + 行动提示。
///
/// 重要：代码支持三阶段 ≠ 已完成前测/训练/后测实验。当前论文阶段只有真实应用日志，
/// `phase` 仅作为数据筛选字段随每条记录上报。
nonisolated enum TrainingPhase: String, Codable, CaseIterable {
    case pretest
    case training
    case posttest

    /// 学习者端是否呈现任何评价性反馈（分数 / 等级 / 颜色 / 曲线 / 行动提示）。
    /// 裸测阶段必须为 false——这是前后测可比性的前提。
    var showsFeedback: Bool { self == .training }

    /// 是否为固定测试词集阶段（前测 / 后测）。
    var isAssessment: Bool { self != .training }

    var localizationKey: String { "phase_\(rawValue)" }
}
