import Combine
import Foundation
import UIKit

@MainActor
final class UserManager: ObservableObject {
    static let shared = UserManager()

    @Published private(set) var profile: UserProfile?

    private static let storageKey = "pt_user_profile"

    private init() {}

    /// 启动时读取本地持久化的用户档案
    func bootstrap() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else { return }
        profile = p
    }

    /// 学生注册（无需班级码）。分组由**后端均衡随机分配**；离线时本地随机兜底。
    func registerStudent(nickname: String?) async throws {
        var p = UserProfile(
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            role: .student,
            nickname: nickname,
            classCode: nil,
            teacherEmail: nil,
            teacherToken: nil,
            experimentGroup: GroupAssignment.randomGroup().rawValue,  // 离线兜底
            nativeLanguage: Locale.current.languageCode,
            registeredAt: Date()
        )
        // 后端均衡分配（在线则以后端返回为准）
        if let assigned = try? await APIClient.shared.registerUser(p),
           ExperimentGroup(rawValue: assigned) != nil {
            p.experimentGroup = assigned
        }
        save(p)
        profile = p
    }

    /// 教师注册；服务器返回 6 位班级码
    func registerTeacher(email: String, password: String, name: String) async throws -> String {
        let resp = try await APIClient.shared.registerTeacher(
            email: email, password: password, name: name)
        let p = UserProfile(
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            role: .teacher,
            nickname: name,
            classCode: resp.classCode,
            teacherEmail: email,
            teacherToken: resp.token,
            experimentGroup: "n/a",
            nativeLanguage: nil,
            registeredAt: Date()
        )
        save(p)
        profile = p
        return resp.classCode
    }

    /// 退出登录 / 切换账号：清除本地档案，回到引导（角色选择）流程。
    /// 注意：
    /// - 不清除实验分组（CLAUDE.md：安装时随机一次，UserDefaults 持久化，不可更改）
    /// - 不清除语言偏好
    func logout() {
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        profile = nil
    }

    private func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
