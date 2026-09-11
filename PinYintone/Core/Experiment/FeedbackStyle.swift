import Foundation

/// 关卡 2 训练阶段的**反馈显示模式**，由学习者自己选择。
///
/// 重要（不要和已废弃的 A/B 分组混为一谈）：
/// - 这是一个**显示偏好**，学习者随时可在设置里切换，默认动态曲线；
/// - **不是**实验条件：没有随机分配、没有反平衡、不绑定词集也不绑定人；
/// - 两种模式的通关标准完全一致（DTW ≤ 0.5），切换不影响评分；
/// - 记录里的 `feedbackMode` 只是"这条记录当时用的哪种显示"，
///   因为是自选的，**不得当作实验条件做组间比较**（会有严重的自选择偏差）。
///
/// 裸测阶段（pretest / posttest）不显示任何反馈，本设置在那两个阶段无效。
nonisolated enum FeedbackStyle: String, Codable, CaseIterable {
    /// 动态 F0 曲线：母语者目标轨迹 + 学习者轨迹
    case dynamicF0
    /// 静态颜色：颜色块 + 方向箭头 + 调号，认知负荷更低
    case staticColor

    var localizationKey: String { "condition_\(rawValue)" }

    /// UserDefaults 键；与 `@AppStorage` 共用，改名需同步 LocalDataPurger
    static let storageKey = "pt_feedback_style"

    /// 当前选择；未选过时默认动态曲线
    static var current: FeedbackStyle {
        UserDefaults.standard.string(forKey: storageKey)
            .flatMap(FeedbackStyle.init(rawValue:)) ?? .dynamicF0
    }
}
