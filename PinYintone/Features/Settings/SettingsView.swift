import SwiftUI

/// 设置页：账户信息 · 语言选择 · 退出登录 · 切换账号
/// 学生端与教师端共用（按角色显示不同字段）
struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var localization = LocalizationManager.shared
    @Environment(\.dismiss) private var dismiss

    #if DEBUG
    @EnvironmentObject private var appState: AppState
    #endif

    @State private var showLogoutConfirm = false
    @State private var showSwitchConfirm = false

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                languageSection
                accountActionsSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("settings_done", comment: "")) { dismiss() }
                }
            }
            // 退出登录确认
            .confirmationDialog(
                NSLocalizedString("settings_logout_confirm", comment: ""),
                isPresented: $showLogoutConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings_logout", comment: ""), role: .destructive) {
                    dismiss()
                    userManager.logout()
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            }
            // 切换账号确认
            .confirmationDialog(
                NSLocalizedString("settings_switch_confirm", comment: ""),
                isPresented: $showSwitchConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings_switch_account", comment: "")) {
                    dismiss()
                    userManager.logout()
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            }
        }
    }

    // MARK: - 账户信息

    private var accountSection: some View {
        Section(NSLocalizedString("settings_account", comment: "")) {
            if let profile {
                LabeledContent(NSLocalizedString("settings_role", comment: ""),
                               value: roleLabel(profile.role))
                if let nick = profile.nickname, !nick.isEmpty {
                    LabeledContent(NSLocalizedString("settings_nickname", comment: ""), value: nick)
                }
                if let code = profile.classCode {
                    LabeledContent(NSLocalizedString("settings_classcode", comment: ""), value: code)
                }
                if let email = profile.teacherEmail {
                    LabeledContent(NSLocalizedString("settings_email", comment: ""), value: email)
                }
                if profile.experimentGroup != "n/a" {
                    LabeledContent(NSLocalizedString("settings_group", comment: ""),
                                   value: profile.experimentGroup)
                }
            }
        }
    }

    // MARK: - 语言选择

    private var languageSection: some View {
        Section(NSLocalizedString("settings_language", comment: "")) {
            ForEach(LocalizationManager.supported, id: \.code) { lang in
                Button {
                    localization.setLanguage(lang.code)
                } label: {
                    HStack {
                        Text(lang.flag)
                        Text(lang.label)
                            .foregroundStyle(.primary)
                        Spacer()
                        if localization.language == lang.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 账户操作

    private var accountActionsSection: some View {
        Section {
            Button {
                showSwitchConfirm = true
            } label: {
                Label(NSLocalizedString("settings_switch_account", comment: ""),
                      systemImage: "person.crop.circle.badge.questionmark")
            }

            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                Label(NSLocalizedString("settings_logout", comment: ""),
                      systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }

    // MARK: - 调试（仅 DEBUG 构建）

    #if DEBUG
    private var debugSection: some View {
        Section {
            Picker("A/B 分组", selection: debugGroupBinding) {
                Text("A · 静态色块").tag(ExperimentGroup.staticColor)
                Text("B · 动态 F0").tag(ExperimentGroup.dynamicF0)
            }
        } header: {
            Text("调试（仅开发构建）")
        } footer: {
            Text("仅预览模式 A/B 视觉效果；进入「声调训练」即可看到。正式分组由班级码前缀决定（1→A / 2→B），此开关不改变已存档分组。")
        }
    }

    private var debugGroupBinding: Binding<ExperimentGroup> {
        Binding(
            get: { appState.group },
            set: { newValue in appState.group = newValue }
        )
    }
    #endif

    // MARK: - Helpers

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .guest:   return NSLocalizedString("role_guest", comment: "")
        case .student: return NSLocalizedString("role_student_short", comment: "")
        case .teacher: return NSLocalizedString("role_teacher_short", comment: "")
        }
    }
}
