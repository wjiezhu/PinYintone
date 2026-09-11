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
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    /// 显示名编辑草稿；进页面时用当前档案填充，提交后写回
    @State private var nicknameDraft = ""
    /// 反馈显示模式（学习者自选）。与训练页共用同一个 UserDefaults 键。
    @AppStorage(FeedbackStyle.storageKey) private var feedbackStyle: FeedbackStyle = .dynamicF0

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        NavigationStack {
            List {
                accountSection
                feedbackStyleSection
                languageSection
                accountActionsSection
                deleteAccountSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { nicknameDraft = profile?.nickname ?? "" }
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
            // 删除账号确认（不可逆，二次确认）
            .confirmationDialog(
                NSLocalizedString("settings_delete_confirm_title", comment: ""),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings_delete_account", comment: ""),
                       role: .destructive) {
                    Task { await performDelete() }
                }
                Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings_delete_confirm_message", comment: ""))
            }
            .alert(NSLocalizedString("settings_delete_failed", comment: ""),
                   isPresented: Binding(get: { deleteError != nil },
                                        set: { if !$0 { deleteError = nil } })) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
            .disabled(isDeleting)
            .overlay { if isDeleting { ProgressView() } }
        }
    }

    /// 先删服务端，成功后再清本地；失败则提示且不清本地，
    /// 避免给用户"已删除"的错觉（数据其实还在后端）。
    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await userManager.deleteAccount()
            dismiss()
        } catch {
            deleteError = NSLocalizedString("settings_delete_failed_message", comment: "")
        }
    }

    // MARK: - 账户信息

    private var accountSection: some View {
        Section(NSLocalizedString("settings_account", comment: "")) {
            if let profile {
                LabeledContent(NSLocalizedString("settings_role", comment: ""),
                               value: roleLabel(profile.role))
                // 显示名可改（升级需求 §4.1）：姓名本就是可选信息，
                // Apple 首次授权给的名字未必是学习者想被称呼的名字
                if profile.role == .student {
                    HStack {
                        Text(NSLocalizedString("settings_nickname", comment: ""))
                        Spacer()
                        TextField(NSLocalizedString("signup_nickname_hint", comment: ""),
                                  text: $nicknameDraft)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { commitNickname() }
                    }
                } else if let nick = profile.nickname, !nick.isEmpty {
                    LabeledContent(NSLocalizedString("settings_nickname", comment: ""), value: nick)
                }
                if let code = profile.classCode {
                    LabeledContent(NSLocalizedString("settings_classcode", comment: ""), value: code)
                }
                if let email = profile.teacherEmail {
                    LabeledContent(NSLocalizedString("settings_email", comment: ""), value: email)
                }
                // 注意：当前研究阶段与 A/B 反平衡排程**不在这里显示**。
                // 裸测的前提是被试不知道自己处在前测还是训练、拿的是哪个条件；
                // 把它们摆在学生可见的设置页等于泄露实验结构。仅调试构建可见。
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

    /// 删除账号（App Store 5.1.1(v) 要求；亦为研究"撤回同意"通道）
    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(NSLocalizedString("settings_delete_account", comment: ""),
                      systemImage: "trash")
            }
        } footer: {
            Text(NSLocalizedString("settings_delete_footer", comment: ""))
        }
    }

    // MARK: - 调试（仅 DEBUG 构建）

    #if DEBUG
    private var debugSection: some View {
        Section {
            LabeledContent("当前阶段",
                           value: NSLocalizedString(
                               ToneSequencer.shared.phase.localizationKey, comment: ""))
        } header: {
            Text("调试（仅开发构建）")
        } footer: {
            Text("研究阶段不在正式构建里显示：裸测的前提是被试不知道自己处在前测还是训练。")
        }
    }
    #endif

    /// 反馈显示模式：学习者自选，随时可换，不影响评分标准。
    private var feedbackStyleSection: some View {
        Section {
            Picker(NSLocalizedString("settings_feedback_style", comment: ""),
                   selection: $feedbackStyle) {
                ForEach(FeedbackStyle.allCases, id: \.self) { style in
                    Text(NSLocalizedString(style.localizationKey, comment: "")).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text(NSLocalizedString("settings_feedback_style", comment: ""))
        } footer: {
            Text(NSLocalizedString("settings_feedback_style_footer", comment: ""))
        }
    }

    // MARK: - Helpers

    /// 提交显示名修改。留空即"不填名字"，与注册时保持一致。
    private func commitNickname() {
        Task { await userManager.updateNickname(nicknameDraft) }
    }

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .student: return NSLocalizedString("role_student_short", comment: "")
        case .teacher: return NSLocalizedString("role_teacher_short", comment: "")
        }
    }
}
