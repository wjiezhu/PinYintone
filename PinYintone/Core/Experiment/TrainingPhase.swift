import Foundation

/// 旧业务表 `training_sessions.phase` 列的取值（升级需求 §3.1，2026-10 修订）。
///
/// **新版不再用「前测 → 训练 → 后测」驱动使用流程**（需求 R06）：
/// 打开声调练习就是普通练习，有反馈、可选词、可随时退出；
/// 自测是学习者从次级菜单主动开始的，可随时取消。
///
/// - `training`：普通练习。显示学习者自选的反馈模式与行动提示。
/// - `selfTest`：可选自测。不显示分数、等级、颜色、曲线、示范或建议。
///   它是学习者自己挑时间做的，**不是规范化的前后测**，不得当作前后测证据。
/// - `pretest` / `posttest`：schemaVersion ≤ 5 里是强制流程的前后测；
///   schemaVersion ≥ 7 起只来自**现场实测**（研究者在场、自愿开始）。两者语义不同，不可合并。
///
/// 本列只为旧表兼容而保留；新版研究数据在 `research_attempts.task_type`
/// （fixed_word / self_test / free_text）。
nonisolated enum TrainingPhase: String, Codable, CaseIterable {
    case pretest
    case training
    case posttest
    case selfTest = "self_test"

    /// 学习者端是否呈现评价性反馈（分数 / 等级 / 颜色 / 曲线 / 行动提示）。
    var showsFeedback: Bool { self == .training }

    /// 是否为不呈现反馈的测试类记录（自测，以及历史上的前测 / 后测）。
    var isAssessment: Bool { self != .training }
}
