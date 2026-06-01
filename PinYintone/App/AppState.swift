import Combine
import Foundation

/// 全局应用状态：A/B 分组、教师模式、教师 Token。
/// 由 PinyintoneApp 注入为 environmentObject，供主页与训练页读取。
@MainActor
final class AppState: ObservableObject {
    /// A/B 实验分组（后端注册时均衡随机分配，存于 profile.experimentGroup）
    @Published var group: ExperimentGroup = .dynamicF0
    /// 是否为教师模式（解锁教师控制台入口）
    @Published var isTeacherMode: Bool = false
    /// 教师 JWT（仅教师模式有值）
    @Published var teacherToken: String?

    /// 从用户档案同步教师状态与实验分组
    func sync(with profile: UserProfile?) {
        isTeacherMode = profile?.role == .teacher
        teacherToken = profile?.teacherToken
        if let raw = profile?.experimentGroup, let g = ExperimentGroup(rawValue: raw) {
            group = g
        }
    }
}
