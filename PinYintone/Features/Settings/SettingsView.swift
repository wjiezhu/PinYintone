import SwiftUI

/// 设置（需求 U06）。按四块组织：账号 · 语言与反馈 · 研究参与 · 帮助与问题反馈。
///
/// 学习记录已移到底部导航的独立页签，不在这里。
/// 「退出研究」与「删除账号」是两件事，分在两块里，各有各的确认。
struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var localization = LocalizationManager.shared
    @ObservedObject private var store = ResearchStore.shared
    @ObservedObject private var config = ResearchConfig.shared

    @State private var showLogoutConfirm = false
    @State private var showSwitchConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showWithdrawConfirm = false
    @State private var showIssueReport = false
    @State private var showHelp = false
    @State private var showResearchFlow = false
    @State private var surveyToOpen: PracticeHomeView.SurveyTarget?
    @State private var isDeleting = false
    @State private var isSyncing = false
    @State private var deleteError: String?
    /// 显示名编辑草稿；进页面时用当前档案填充，提交后写回
    @State private var nicknameDraft = ""
    /// 反馈显示模式（学习者自选）。与练习页共用同一个 UserDefaults 键。
    @AppStorage(FeedbackStyle.storageKey) private var feedbackStyle: FeedbackStyle = .dynamicF0

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        List {
            accountSection
            languageSection
            feedbackStyleSection
            if profile?.role == .student { researchSection }
            supportSection
            accountActionsSection
            #if DEBUG
            debugSection
            #endif
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { nicknameDraft = profile?.nickname ?? "" }
        .sheet(isPresented: $showIssueReport) { IssueReportView() }
        .sheet(isPresented: $showHelp) { HelpView() }
        .sheet(isPresented: $showResearchFlow) { ResearchJoinFlowView() }
        .sheet(item: $surveyToOpen) { ResearchSurveySheet(formKey: $0.formKey) }
        .confirmationDialog(NSLocalizedString("settings_logout_confirm", comment: ""),
                            isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("settings_logout", comment: ""), role: .destructive) {
                userManager.logout()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        .confirmationDialog(NSLocalizedString("settings_switch_confirm", comment: ""),
                            isPresented: $showSwitchConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("settings_switch_account", comment: "")) {
                userManager.logout()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        }
        // 删除账号确认（不可逆，二次确认）
        .confirmationDialog(NSLocalizedString("settings_delete_confirm_title", comment: ""),
                            isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("settings_delete_account", comment: ""), role: .destructive) {
                Task { await performDelete() }
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settings_delete_confirm_message", comment: ""))
        }
        // 退出研究确认。与删除账号分开：退出后账号与学习记录都还在。
        .confirmationDialog(NSLocalizedString("research_withdraw_confirm_title", comment: ""),
                            isPresented: $showWithdrawConfirm, titleVisibility: .visible) {
            Button(NSLocalizedString("research_withdraw", comment: ""), role: .destructive) {
                ResearchEnrollment.withdraw()
            }
            Button(NSLocalizedString("cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("research_withdraw_confirm_message", comment: ""))
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

    /// 先删服务端，成功后再清本地；失败则提示且不清本地，
    /// 避免给用户「已删除」的错觉（数据其实还在后端）。
    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await userManager.deleteAccount()
        } catch {
            deleteError = NSLocalizedString("settings_delete_failed_message", comment: "")
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        Section(NSLocalizedString("settings_account", comment: "")) {
            if let profile {
                LabeledContent(NSLocalizedString("settings_role", comment: ""),
                               value: roleLabel(profile.role))
                // 显示名可改：姓名本就是可选信息
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
                // 班级码与邮箱只有教师账号有；学生界面不出现班级码
                if profile.role == .teacher, let code = profile.classCode {
                    LabeledContent(NSLocalizedString("settings_classcode", comment: ""), value: code)
                }
                if let email = profile.teacherEmail {
                    LabeledContent(NSLocalizedString("settings_email", comment: ""), value: email)
                }
            }
        }
    }

    // MARK: - 语言与反馈

    private var languageSection: some View {
        Section(NSLocalizedString("settings_language", comment: "")) {
            ForEach(LocalizationManager.supported, id: \.code) { lang in
                Button {
                    localization.setLanguage(lang.code)
                } label: {
                    HStack {
                        Text(lang.label)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if localization.language == lang.code {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityAddTraits(localization.language == lang.code ? .isSelected : [])
                .accessibilityIdentifier("settings.language.\(lang.code)")
            }
        }
    }

    /// 反馈显示模式：学习者自选，随时可换，不影响评分标准。
    private var feedbackStyleSection: some View {
        Section {
            Picker(NSLocalizedString("settings_feedback_style", comment: ""),
                   selection: $feedbackStyle) {
                ForEach([FeedbackStyle.staticColor, .dynamicF0], id: \.self) { style in
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

    // MARK: - 研究参与

    /// 当前状态 + 该状态下能做的事。只说学习者需要知道的，
    /// 不出现配置编号、窗口时间、接口错误之类的技术细节。
    private var researchSection: some View {
        let state = store.state
        return Section {
            LabeledContent(NSLocalizedString("research_status", comment: "")) {
                Text(NSLocalizedString(researchStatusKey, comment: ""))
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityIdentifier("settings.researchStatus")

            switch state.participation {
            case .notAsked, .declined, .consentedPending:
                if ResearchEnrollment.canJoinNow() {
                    Button {
                        showResearchFlow = true
                    } label: {
                        Label(NSLocalizedString(state.participation == .consentedPending
                                                ? "research_resume" : "research_join", comment: ""),
                              systemImage: "person.badge.plus")
                    }
                    .accessibilityIdentifier("settings.researchJoin")
                }
            case .ineligible:
                // 关键题当时没答、所以没法判定的人，可以主动回来重新填
                if state.eligibility == "pending", config.isOpen() {
                    Button {
                        ResearchConsent.restart()
                        showResearchFlow = true
                    } label: {
                        Label(NSLocalizedString("research_rejoin", comment: ""),
                              systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("settings.researchRejoin")
                }
            case .enrolled:
                ForEach([SurveyCenter.preKey, SurveyCenter.postKey], id: \.self) { key in
                    if let record = state.surveys[key] { surveyRow(record) }
                }
                if hasUnsyncedResearchData {
                    Button {
                        isSyncing = true
                        Task {
                            await ResearchUploader.shared.flush()
                            isSyncing = false
                        }
                    } label: {
                        HStack {
                            Label(NSLocalizedString("research_sync_now", comment: ""),
                                  systemImage: "arrow.triangle.2.circlepath")
                            if isSyncing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isSyncing)
                    .accessibilityIdentifier("settings.researchSync")
                }
                Button(role: .destructive) {
                    showWithdrawConfirm = true
                } label: {
                    Label(NSLocalizedString("research_withdraw", comment: ""),
                          systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("settings.researchWithdraw")
            case .withdrawn:
                EmptyView()
            }
        } header: {
            Text(NSLocalizedString("research_section", comment: ""))
        } footer: {
            Text(NSLocalizedString("research_section_footer", comment: ""))
        }
    }

    private var researchStatusKey: String {
        let state = store.state
        switch state.participation {
        case .notAsked, .declined:
            return config.isOpen() ? "research_status_not_joined" : "research_status_closed"
        case .consentedPending:
            return "research_status_consented"
        case .ineligible:
            return "research_status_ineligible"
        case .enrolled:
            // 服务端确认纳入了，但背景表还没送达：如实显示「待提交」
            return state.backgroundAcked ? "research_status_enrolled" : "research_status_pending"
        case .withdrawn:
            return state.pendingWithdrawal == nil
                ? "research_status_withdrawn" : "research_status_withdrawn_pending"
        }
    }

    private var hasUnsyncedResearchData: Bool {
        !SurveyCenter.recordsNeedingUpload(in: store.state).isEmpty
            || !ResearchAttemptLog.shared.pending.isEmpty
            || !ResearchEventLog.shared.pending.isEmpty
    }

    /// 一份问卷的状态行。还能填的可以点开继续；已保存未送达的可以点开看状态并重试。
    private func surveyRow(_ record: SurveyRecord) -> some View {
        let status = SurveyDisplayStatus(record)
        let openable = record.isResumable || status == .savedWaitingForNetwork
        return Button {
            surveyToOpen = .init(formKey: record.formKey)
        } label: {
            HStack {
                Text(NSLocalizedString(record.formKey == SurveyCenter.preKey
                                       ? "survey_pre_name" : "survey_post_name", comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(NSLocalizedString(status.localizationKey, comment: ""))
                    .foregroundStyle(status == .savedWaitingForNetwork || status == .notAccepted
                                     ? Theme.warning : Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                if openable {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(!openable)
        .accessibilityIdentifier("settings.survey.\(record.formKey)")
    }

    // MARK: - 帮助与问题反馈

    /// 帮助对所有人可用。报告问题入口**始终可用**：录音起不来的人根本进不了结果页。
    /// 没有研究身份时走邮件，不假装反馈已进研究库（见 IssueReportView）。
    private var supportSection: some View {
        Section(NSLocalizedString("settings_support", comment: "")) {
            Button {
                showHelp = true
            } label: {
                Label(NSLocalizedString("help_title", comment: ""), systemImage: "questionmark.circle")
            }
            .accessibilityIdentifier("settings.help")
            Button {
                showIssueReport = true
            } label: {
                Label(NSLocalizedString("issue_title", comment: ""),
                      systemImage: "exclamationmark.bubble")
            }
            .accessibilityIdentifier("settings.issue")
        }
    }

    // MARK: - 账号操作

    private var accountActionsSection: some View {
        Section {
            Button {
                showSwitchConfirm = true
            } label: {
                Label(NSLocalizedString("settings_switch_account", comment: ""),
                      systemImage: "person.crop.circle.badge.questionmark")
            }
            .accessibilityIdentifier("settings.switchAccount")

            Button {
                showLogoutConfirm = true
            } label: {
                Label(NSLocalizedString("settings_logout", comment: ""),
                      systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("settings.logout")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label(NSLocalizedString("settings_delete_account", comment: ""),
                      systemImage: "trash")
            }
            .accessibilityIdentifier("settings.deleteAccount")
        } footer: {
            Text(NSLocalizedString("settings_delete_footer", comment: ""))
        }
    }

    // MARK: - 调试（仅 DEBUG 构建）

    #if DEBUG
    /// 验收与界面测试用：本机研究队列的实际状态。正式构建里不存在。
    private var debugSection: some View {
        let s = store.state
        return Section {
            LabeledContent("participation", value: s.participation.rawValue)
                .accessibilityIdentifier("debug.participation")
            LabeledContent("collecting", value: ResearchGate.shouldCollect() ? "yes" : "no")
                .accessibilityIdentifier("debug.collecting")
            LabeledContent("qualifying", value: "\(s.qualifyingCount)")
                .accessibilityIdentifier("debug.qualifying")
            LabeledContent("pending attempts", value: "\(ResearchAttemptLog.shared.pending.count)")
                .accessibilityIdentifier("debug.pendingAttempts")
            LabeledContent("pending events", value: "\(ResearchEventLog.shared.pending.count)")
                .accessibilityIdentifier("debug.pendingEvents")
            LabeledContent("pending surveys",
                           value: "\(SurveyCenter.recordsNeedingUpload(in: s).count)")
                .accessibilityIdentifier("debug.pendingSurveys")
            LabeledContent("rejected by server",
                           value: "\(store.deadLetterCount(queue: "attempts") + store.deadLetterCount(queue: "events") + store.deadLetterCount(queue: "advice"))")
                .accessibilityIdentifier("debug.deadLetters")
            LabeledContent("build", value: "\(AppEnvironment.appVersion) (\(AppEnvironment.buildNumber))")
        } header: {
            Text("调试（仅开发构建）")
        }
    }
    #endif

    // MARK: - Helpers

    /// 提交显示名修改。留空即「不填名字」，与注册时保持一致。
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
