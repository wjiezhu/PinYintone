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

    /// 学生/游客注册（classCode 为 nil 时注册为游客）
    func registerStudent(nickname: String?, classCode: String?) async throws {
        // 有班级码则先验证有效性
        if let code = classCode {
            let valid = try await APIClient.shared.verifyClassCode(code)
            guard valid else { throw RegisterError.invalidClassCode }
        }
        let p = UserProfile(
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            role: classCode == nil ? .guest : .student,
            nickname: nickname,
            classCode: classCode,
            teacherEmail: nil,
            teacherToken: nil,
            experimentGroup: GroupAssignment.shared.group.rawValue,
            nativeLanguage: Locale.current.languageCode,
            registeredAt: Date()
        )
        // 上报云端（游客同样上报，便于研究数据收集），失败不阻塞本地注册
        try? await APIClient.shared.registerUser(p)
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

    /// 游客绑定班级码，升级为 student
    func bindClassCode(_ code: String) async throws {
        guard var p = profile, p.role == .guest else { return }
        let valid = try await APIClient.shared.verifyClassCode(code)
        guard valid else { throw RegisterError.invalidClassCode }
        p.classCode = code
        p.role = .student
        try? await APIClient.shared.updateUserBinding(deviceID: p.deviceID, classCode: code)
        save(p)
        profile = p
    }

    private func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
