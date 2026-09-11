import Combine
import Foundation

/// 全局应用状态：教师模式与教师 Token。
/// 由 PinyintoneApp 注入为 environmentObject，供主页与训练页读取。
///
/// 这里不保存任何实验分组信息：关卡 2 已取消 A/B，训练阶段一律使用
/// 动态 F0 可视化，没有需要按人或按词集保存的条件。
@MainActor
final class AppState: ObservableObject {
    /// 是否为教师模式（解锁教师控制台入口）
    @Published var isTeacherMode: Bool = false
    /// 教师 JWT（仅教师模式有值）
    @Published var teacherToken: String?

    /// 从用户档案同步教师状态
    func sync(with profile: UserProfile?) {
        isTeacherMode = profile?.role == .teacher
        teacherToken = profile?.teacherToken
    }
}
