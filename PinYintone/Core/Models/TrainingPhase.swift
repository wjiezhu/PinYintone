import Foundation

/// 实验阶段（受试内前后测设计）。随每条声调训练记录上报，
/// 导出时据此算"后测 − 前测"增益，并把训练期数据与裸测基线分开。
///
/// - pretest：前测。裸测——录音并后台评分上报，但**不给任何反馈**
///   （不显示分数/等级/F0 或颜色可视化），避免测试本身变成训练。
/// - training：训练期。正常给反馈；受试内 A/B——同一被试的不同词集
///   分别用静态色块(A)与动态曲线(B)呈现。
/// - posttest：后测。同前测，裸测无反馈，用固定测试词集与前测同题。
enum TrainingPhase: String, Codable, CaseIterable {
    case pretest
    case training
    case posttest

    /// 该阶段是否向学习者展示反馈（分数/等级/可视化）。
    /// 前测与后测为裸测，不展示；仅训练期展示。
    var showsFeedback: Bool { self == .training }
}
