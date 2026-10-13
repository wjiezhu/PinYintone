import Combine
import Foundation
import UIKit

@MainActor
final class UserManager: ObservableObject {

    // 勿删：见 CLAUDE.md 禁令 18（隐式析构在 iOS 18.5 / 26.2 上实测崩溃）
    nonisolated deinit {}

    static let shared = UserManager()

    @Published private(set) var profile: UserProfile?

    private static let storageKey = "pt_user_profile"

    private init() {}

    /// 启动时读取本地持久化的用户档案
    func bootstrap() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            ResearchStore.shared.activate(for: nil)
            return
        }
        profile = p
        ResearchStore.shared.activate(for: p)
    }

    /// 学生注册（Sign in with Apple）。后端按 deviceID / Apple ID 幂等建档，
    /// 不再分配任何实验分组或反馈条件。
    func registerStudent(appleUserID: String, nickname: String?,
                         spokenLanguages: [SpokenLanguage] = []) async throws {
        let p = UserProfile(
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            role: .student,
            appleUserID: appleUserID,
            nickname: nickname,
            classCode: nil,
            teacherEmail: nil,
            teacherToken: nil,
            nativeLanguage: Locale.current.language.languageCode?.identifier,
            spokenLanguages: spokenLanguages.map(\.rawValue),
            registeredAt: Date()
        )
        // 注册到后端（失败不阻塞本地建档，下次同步补上；参加研究前也会再补一次）
        _ = try? await APIClient.shared.registerUser(p)
        save(p)
        profile = p
        // 研究状态按账号隔离：切到这个账号自己的那一份
        ResearchStore.shared.activate(for: p)
    }

    /// 修改显示名（升级需求 §4.1：姓名可选，首次授权后允许学习者自行修改）。
    ///
    /// 空字符串视为"不填名字"，存 nil。后端 `student/register` 幂等，
    /// 重新上报只更新 nickname。
    func updateNickname(_ newName: String?) async {
        guard var p = profile, p.role == .student else { return }
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard resolved != p.nickname else { return }
        p.nickname = resolved
        save(p)
        profile = p
        // 后端不可达时本地已改好，下次注册/同步会补上
        _ = try? await APIClient.shared.registerUser(p)
    }

    /// 教师注册；服务器返回 6 位班级码
    func registerTeacher(email: String, password: String, name: String) async throws -> String {
        let resp = try await APIClient.shared.registerTeacher(
            email: email, password: password, name: name)
        let p = UserProfile(
            deviceID: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
            role: .teacher,
            appleUserID: nil,
            nickname: name,
            classCode: resp.classCode,
            teacherEmail: email,
            teacherToken: resp.token,
            nativeLanguage: nil,
            spokenLanguages: nil,
            registeredAt: Date()
        )
        save(p)
        profile = p
        ResearchStore.shared.activate(for: p)     // 教师账号没有研究状态
        return resp.classCode
    }

    /// 退出登录 / 切换账号：清除本地档案，回到登录流程。不清除语言偏好。
    ///
    /// 研究状态**按账号隔离**：登出后当前没有研究身份，不采集；
    /// 这个账号的研究状态与待传队列留在它自己的存储域里，等它重新登录时接着用，
    /// 下一个登录的人看不到也用不到。
    func logout() {
        LearnerRecordingStore.shared.clear()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        profile = nil
        ResearchStore.shared.activate(for: nil)
    }

    /// 删除账号：清空服务端与本机的全部个人数据，回到引导流程。
    /// App Store 审核指南 5.1.1(v) 强制要求（有注册即须可删除）；
    /// 同时是研究伦理上的「撤回同意」通道——被试有权随时退出并抹除其数据。
    /// 服务端删除失败时抛错，避免给用户"已删除"的错觉。
    func deleteAccount() async throws {
        guard let profile else { return }
        try await APIClient.shared.deleteAccount(
            deviceID: profile.deviceID, appleUserID: profile.appleUserID)

        // 服务端删除成功后再清本地：本地训练记录、练习位置、尝试计数，
        // 以及这个账号的研究状态与全部待传内容（服务端已同时记为退出研究）
        LocalDataPurger.purgeAll()
        ResearchStore.shared.purgeCurrentAccount()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        self.profile = nil
    }

    private func save(_ profile: UserProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
