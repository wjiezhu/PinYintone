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
    @State private var wechatCopied = false
    @State private var deleteError: String?
    /// 显示名编辑草稿；进页面时用当前档案填充，提交后写回
    @State private var nicknameDraft = ""
    /// 反馈显示模式（学习者自选）。与练习页共用同一个 UserDefaults 键。
    @AppStorage(FeedbackStyle.storageKey) private var feedbackStyle: FeedbackStyle = .dynamicF0

    private var profile: UserProfile? { userManager.profile }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
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
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, Theme.Space.s)
            .padding(.bottom, Theme.Space.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.secondaryBackground)
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

    // MARK: - 版式

    /// 一组设置：小标题 + 一块内容面（行间细线）+ 可选的说明文字
    private func group(_ titleKey: String?, footerKey: String? = nil,
                       rows: [AnyView]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let titleKey { SectionTitle(key: titleKey) }
            GroupedCard {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { RowDivider() }
                    row
                }
            }
            if let footerKey {
                Text(NSLocalizedString(footerKey, comment: ""))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 只读的一行：左边名称，右边取值
    private func valueRow(_ titleKey: String, value: String, valueID: String = "") -> AnyView {
        AnyView(
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(NSLocalizedString(titleKey, comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: Theme.Space.s)
                Text(value)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(valueID)
            }
            .font(.body)
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: Theme.minTap + 4)
        )
    }

    /// 可点的一行：图标 + 名称。不可逆的操作用红色并配图标，不单靠颜色。
    private func actionRow(_ titleKey: String, icon: String, id: String,
                           destructive: Bool = false, busy: Bool = false,
                           action: @escaping () -> Void) -> AnyView {
        AnyView(
            Button(action: action) {
                HStack(spacing: Theme.Space.m) {
                    Image(systemName: icon)
                        .font(.body.weight(.medium))
                        .foregroundStyle(destructive ? Theme.learnerAccent : Theme.primary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(NSLocalizedString(titleKey, comment: ""))
                        .font(.body)
                        .foregroundStyle(destructive ? Theme.learnerAccent : Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if busy { ProgressView() }
                }
                .padding(.vertical, Theme.Space.m)
                .frame(minHeight: Theme.minTap + 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .accessibilityIdentifier(id)
        )
    }

    // MARK: - 账号

    private var accountSection: some View {
        var rows: [AnyView] = []
        if let profile {
            rows.append(valueRow("settings_role", value: roleLabel(profile.role)))
            // 显示名可改：姓名本就是可选信息
            if profile.role == .student {
                rows.append(AnyView(
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                        Text(NSLocalizedString("settings_nickname", comment: ""))
                            .foregroundStyle(Theme.textPrimary)
                        TextField(NSLocalizedString("signup_nickname_hint", comment: ""),
                                  text: $nicknameDraft)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { commitNickname() }
                    }
                    .font(.body)
                    .padding(.vertical, Theme.Space.m)
                    .frame(minHeight: Theme.minTap + 4)
                ))
            } else if let nick = profile.nickname, !nick.isEmpty {
                rows.append(valueRow("settings_nickname", value: nick))
            }
            // 班级码与邮箱只有教师账号有；学生界面不出现班级码
            if profile.role == .teacher, let code = profile.classCode {
                rows.append(valueRow("settings_classcode", value: code))
            }
            if let email = profile.teacherEmail {
                rows.append(valueRow("settings_email", value: email))
            }
        }
        return group("settings_account", rows: rows)
    }

    // MARK: - 语言与反馈

    private var languageSection: some View {
        let rows = LocalizationManager.supported.map { lang -> AnyView in
            let current = localization.language == lang.code
            return AnyView(
                Button {
                    localization.setLanguage(lang.code)
                } label: {
                    HStack {
                        Text(lang.label)
                            .font(.body.weight(current ? .semibold : .regular))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if current {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, Theme.Space.m)
                    .frame(minHeight: Theme.minTap + 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(current ? .isSelected : [])
                .accessibilityIdentifier("settings.language.\(lang.code)")
            )
        }
        return group("settings_language", rows: rows)
    }

    /// 反馈显示模式：学习者自选，随时可换，不影响评分标准。
    private var feedbackStyleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionTitle(key: "settings_feedback_style")
            Picker(NSLocalizedString("settings_feedback_style", comment: ""),
                   selection: $feedbackStyle) {
                ForEach([FeedbackStyle.staticColor, .dynamicF0], id: \.self) { style in
                    Text(NSLocalizedString(style.localizationKey, comment: "")).tag(style)
                }
            }
            .pickerStyle(.segmented)
            Text(NSLocalizedString("settings_feedback_style_footer", comment: ""))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 研究参与

    /// 当前状态 + 该状态下能做的事。只说学习者需要知道的，
    /// 不出现配置编号、窗口时间、接口错误之类的技术细节。
    private var researchSection: some View {
        let state = store.state
        var rows: [AnyView] = [
            valueRow("research_status", value: NSLocalizedString(researchStatusKey, comment: ""),
                     valueID: "settings.researchStatus")
        ]

        switch state.participation {
        case .notAsked, .declined, .consentedPending:
            if ResearchEnrollment.canJoinNow() {
                rows.append(actionRow(state.participation == .consentedPending
                                      ? "research_resume" : "research_join",
                                      icon: "person.badge.plus", id: "settings.researchJoin") {
                    showResearchFlow = true
                })
            }
        case .ineligible:
            // 关键题当时没答、所以没法判定的人，可以主动回来重新填
            if state.eligibility == "pending", config.isOpen() {
                rows.append(actionRow("research_rejoin", icon: "arrow.counterclockwise",
                                      id: "settings.researchRejoin") {
                    ResearchConsent.restart()
                    showResearchFlow = true
                })
            }
        case .enrolled:
            for key in [SurveyCenter.preKey, SurveyCenter.postKey] {
                if let record = state.surveys[key] { rows.append(AnyView(surveyRow(record))) }
            }
            if hasUnsyncedResearchData {
                rows.append(actionRow("research_sync_now", icon: "arrow.triangle.2.circlepath",
                                      id: "settings.researchSync", busy: isSyncing) {
                    isSyncing = true
                    Task {
                        await ResearchUploader.shared.flush()
                        isSyncing = false
                    }
                })
            }
            rows.append(actionRow(wechatCopied ? "research_wechat_copied" : "research_wechat_copy",
                                  icon: "message", id: "settings.researchWeChat") {
                UIPasteboard.general.string = ResearchConsent.wechatID
                wechatCopied = true
            })
            rows.append(actionRow("research_withdraw", icon: "rectangle.portrait.and.arrow.right",
                                  id: "settings.researchWithdraw", destructive: true) {
                showWithdrawConfirm = true
            })
        case .withdrawn:
            break
        }
        return group("research_section", footerKey: "research_section_footer", rows: rows)
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
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Text(NSLocalizedString(record.formKey == SurveyCenter.preKey
                                       ? "survey_pre_name" : "survey_post_name", comment: ""))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Theme.Space.s)
                Text(NSLocalizedString(status.localizationKey, comment: ""))
                    .foregroundStyle(status == .savedWaitingForNetwork || status == .notAccepted
                                     ? Theme.warning : Theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                if openable {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .font(.body)
            .padding(.vertical, Theme.Space.m)
            .frame(minHeight: Theme.minTap + 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!openable)
        .accessibilityIdentifier("settings.survey.\(record.formKey)")
    }

    // MARK: - 帮助与问题反馈

    /// 帮助对所有人可用。报告问题入口**始终可用**：录音起不来的人根本进不了结果页。
    /// 没有研究身份时走邮件，不假装反馈已进研究库（见 IssueReportView）。
    private var supportSection: some View {
        group("settings_support", rows: [
            actionRow("help_title", icon: "questionmark.circle", id: "settings.help") {
                showHelp = true
            },
            actionRow("issue_title", icon: "exclamationmark.bubble", id: "settings.issue") {
                showIssueReport = true
            },
        ])
    }

    // MARK: - 账号操作

    private var accountActionsSection: some View {
        group(nil, footerKey: "settings_delete_footer", rows: [
            actionRow("settings_switch_account", icon: "person.2", id: "settings.switchAccount") {
                showSwitchConfirm = true
            },
            actionRow("settings_logout", icon: "rectangle.portrait.and.arrow.right",
                      id: "settings.logout") {
                showLogoutConfirm = true
            },
            actionRow("settings_delete_account", icon: "trash", id: "settings.deleteAccount",
                      destructive: true) {
                showDeleteConfirm = true
            },
        ])
    }

    // MARK: - 调试（仅 DEBUG 构建）

    #if DEBUG
    /// 验收与界面测试用：本机研究队列的实际状态。正式构建里不存在。
    private var debugSection: some View {
        let s = store.state
        let rejected = store.deadLetterCount(queue: "attempts")
            + store.deadLetterCount(queue: "events") + store.deadLetterCount(queue: "advice")
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("调试（仅开发构建）")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            debugRow("participation", s.participation.rawValue)
            debugRow("collecting", ResearchGate.shouldCollect() ? "yes" : "no")
            debugRow("backgroundAcked", s.backgroundAcked ? "yes" : "no")
            debugRow("qualifying", "\(s.qualifyingCount)")
            debugRow("pendingAttempts", "\(ResearchAttemptLog.shared.pending.count)")
            debugRow("pendingEvents", "\(ResearchEventLog.shared.pending.count)")
            debugRow("pendingSurveys", "\(SurveyCenter.recordsNeedingUpload(in: s).count)")
            debugRow("pendingWithdrawal", s.pendingWithdrawal == nil ? "no" : "yes")
            debugRow("rejectedByServer", "\(rejected)")
            debugRow("build", "\(AppEnvironment.appVersion) (\(AppEnvironment.buildNumber))")
        }
    }

    private func debugRow(_ name: String, _ value: String) -> some View {
        Text("\(name)=\(value)")
            .font(.footnote.monospaced())
            .foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("debug.\(name)")
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
