import SwiftUI

/// 自愿参加研究的流程（需求 R02）：知情说明 → 背景表 → 资格判定 → 服务端纳入 →
/// 首次练习前问卷邀请。
///
/// 这是一个**可以随时离开**的 sheet，不是启动时必须完成的任务：
/// - 任何一步都能关掉去练习；状态已保存，之后从「设置 → 参与研究」回来接着做。
/// - 纳入请求失败（断网、超时）给出重试与稍后再说两个出口，不无限转圈。
/// - 不符合条件的人看到一句平实的说明后回到 App，功能不受任何影响。
///
/// 界面完全由 `ResearchStore` 的状态驱动，所以中途杀掉 App 再进来，
/// 会停在该停的那一步。
struct ResearchJoinFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ResearchStore.shared
    @ObservedObject private var config = ResearchConfig.shared

    @State private var isEnrolling = false
    @State private var enrollError: ResearchEnrollment.EnrollError?
    @State private var showPreSurvey = false

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if showsCloseButton {
                            Button(NSLocalizedString("common_close", comment: "")) { dismiss() }
                                .accessibilityIdentifier("research.close")
                        }
                    }
                }
        }
        .tint(Theme.primary)
        .interactiveDismissDisabled(isEnrolling)
    }

    /// 背景表有自己的「稍后填写」，不再叠一个关闭键
    private var showsCloseButton: Bool {
        !(store.state.participation == .consentedPending && !ResearchEnrollment.isAwaitingEnrollment)
    }

    @ViewBuilder
    private var content: some View {
        switch store.state.participation {
        case .notAsked, .declined:
            if config.isOpen() {
                ResearchConsentView { agreed in
                    if !agreed { dismiss() }
                }
            } else {
                notOpenView
            }
        case .consentedPending:
            if ResearchEnrollment.isAwaitingEnrollment {
                enrollingView
            } else if !config.isOpen() {
                notOpenView
            } else {
                backgroundForm
            }
        case .enrolled:
            if showPreSurvey {
                ResearchSurveyContent(formKey: SurveyCenter.preKey) { dismiss() }
            } else {
                enrolledView
            }
        case .ineligible:
            messageView(icon: "info.circle", title: "research_ineligible_title",
                        body: "research_ineligible_body")
        case .withdrawn:
            messageView(icon: "info.circle", title: "research_status_withdrawn",
                        body: "research_withdrawn_body")
        }
    }

    // MARK: - 背景表

    @ViewBuilder
    private var backgroundForm: some View {
        if let form = SurveyFormLoader.bundled[SurveyCenter.backgroundKey] {
            SurveyFormView(
                form: form,
                // 语言在开始作答时定下，恢复草稿时仍用它
                language: store.state.backgroundLanguage ?? LocalizationManager.shared.language,
                draft: store.state.backgroundDraft ?? SurveyDraft(),
                onDraftChange: { draft in
                    store.update { s in
                        s.backgroundDraft = draft
                        s.backgroundStartedAt = s.backgroundStartedAt ?? Date()
                        s.backgroundLanguage = s.backgroundLanguage
                            ?? LocalizationManager.shared.language
                    }
                },
                onSubmit: { answers in submitBackground(form: form, answers: answers) },
                onLater: { dismiss() })
        } else {
            // 定义加载不出来：不空白卡住，也不猜
            messageView(icon: "exclamationmark.triangle", title: "research_not_open_title",
                        body: "research_not_open_body")
        }
    }

    private func submitBackground(form: SurveyForm, answers: [SurveyAnswer]) {
        let now = Date()
        let outcome = SurveyOutcome(
            formKey: form.formKey, formVersion: form.formVersion,
            translationVersion: form.translationVersion,
            language: store.state.backgroundLanguage ?? LocalizationManager.shared.language,
            answers: answers,
            status: SurveyCenter.status(for: answers).rawValue,
            startedAt: store.state.backgroundStartedAt ?? now,
            submittedAt: now)
        store.update { s in
            s.backgroundDraft = nil
            s.backgroundStartedAt = nil
            s.backgroundLanguage = nil
        }
        runEnrollment { try await ResearchEnrollment.submitBackground(outcome) }
    }

    // MARK: - 纳入

    private func runEnrollment(_ work: @escaping () async throws -> Void) {
        enrollError = nil
        isEnrolling = true
        Task {
            do {
                try await work()
            } catch let error as ResearchEnrollment.EnrollError {
                enrollError = error
            } catch {
                enrollError = .network
            }
            isEnrolling = false
        }
    }

    /// 已判合格、等服务端确认。**不是一个只会转圈的页面**：
    /// 失败时给出原因与两个出口——重试，或者先去练习稍后再说。
    private var enrollingView: some View {
        VStack(spacing: Theme.Space.l) {
            Spacer()
            if isEnrolling {
                ProgressView()
                Text(NSLocalizedString("research_enrolling", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                StatusLabel(kind: .warning, text: NSLocalizedString(enrollErrorKey, comment: ""))
                    .multilineTextAlignment(.leading)
                Text(NSLocalizedString("research_enroll_saved_hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !isEnrolling {
                VStack(spacing: Theme.Space.s) {
                    if canRetryEnrollment {
                        Button {
                            runEnrollment { try await ResearchEnrollment.retryEnrollment() }
                        } label: {
                            Text(NSLocalizedString("common_retry", comment: ""))
                                .frame(maxWidth: .infinity, minHeight: 28)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("research.retryEnroll")
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("research_continue_later", comment: ""))
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("research.later")
                }
            }
        }
        .padding(Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("research.enrolling")
        .navigationTitle(NSLocalizedString("consent_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 回到这一步（比如从设置里重新进入）时自动再试一次
            if !isEnrolling, enrollError == nil {
                runEnrollment { try await ResearchEnrollment.retryEnrollment() }
            }
        }
    }

    private var canRetryEnrollment: Bool {
        if case .refused = enrollError { return false }
        return true
    }

    private var enrollErrorKey: String {
        switch enrollError {
        case .refused: return "research_enroll_refused"
        case .notOpen: return "research_not_open_body"
        default:       return "consent_enroll_failed"
        }
    }

    // MARK: - 已参与：首次练习前问卷邀请

    private var enrolledView: some View {
        let pre = store.state.surveys[SurveyCenter.preKey]
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            StatusLabel(kind: .success, text: NSLocalizedString("research_enrolled_title", comment: ""))
                .font(.title3.weight(.semibold))
                .accessibilityIdentifier("research.enrolledTitle")
            Text(NSLocalizedString(store.state.backgroundAcked
                                   ? "research_enrolled_body" : "research_enrolled_pending_body",
                                   comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if pre?.isResumable == true {
                Divider()
                Text(NSLocalizedString("survey_pre_invite_title", comment: ""))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(NSLocalizedString("survey_pre_invite_body", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if pre?.isResumable == true {
                SurveyInvitationButtons(
                    onStart: { showPreSurvey = true },
                    onLater: {
                        SurveyCenter.deferSurvey(SurveyCenter.preKey)
                        dismiss()
                    },
                    onDecline: {
                        SurveyCenter.decline(SurveyCenter.preKey)
                        dismiss()
                    })
            } else {
                Button {
                    dismiss()
                } label: {
                    Text(NSLocalizedString("research_start_practice", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("research.done")
            }
        }
        .padding(Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("consent_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 说明页

    private var notOpenView: some View {
        messageView(icon: "calendar.badge.clock", title: "research_not_open_title",
                    body: "research_not_open_body")
    }

    private func messageView(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            IconTile(systemName: icon, size: 56)
            Text(NSLocalizedString(title, comment: ""))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("research.message.\(title)")
            Text(NSLocalizedString(body, comment: ""))
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(NSLocalizedString("research_start_practice", comment: ""))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("research.done")
        }
        .padding(Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("consent_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 问卷邀请的三个出口：现在填写 · 稍后填写 · 不填写。
/// 三者并列可见——「稍后」与「不填写」是不同的选择，分别记录。
struct SurveyInvitationButtons: View {
    let onStart: () -> Void
    let onLater: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Button(action: onStart) {
                Text(NSLocalizedString("survey_start_now", comment: ""))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("surveyInvite.start")

            Button(action: onLater) {
                Text(NSLocalizedString("survey_later", comment: ""))
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("surveyInvite.later")

            Button(action: onDecline) {
                Text(NSLocalizedString("survey_decline", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("surveyInvite.decline")
        }
    }
}

/// 一份问卷（前置或使用后）的作答与提交结果。可嵌在 NavigationStack 里。
///
/// 提交后的状态**如实显示**：服务端确认了才是「已提交」；只存在本机的，
/// 显示「已保存，等待联网提交」并给出重试——不吞掉错误后假装成功。
struct ResearchSurveyContent: View {
    let formKey: String
    let onClose: () -> Void

    @ObservedObject private var store = ResearchStore.shared
    @State private var isRetrying = false

    var body: some View {
        if let record = store.state.surveys[formKey],
           let form = SurveyFormLoader.bundled[formKey] {
            if record.isResumable {
                SurveyFormView(
                    form: form,
                    language: record.language,
                    draft: record.draft ?? SurveyDraft(),
                    onDraftChange: { SurveyCenter.saveDraft(formKey, $0) },
                    onSubmit: { SurveyCenter.submit(formKey, answers: $0) },
                    onLater: {
                        SurveyCenter.deferSurvey(formKey)
                        onClose()
                    },
                    onDecline: {
                        SurveyCenter.decline(formKey)
                        onClose()
                    })
            } else {
                resultView(record, title: form.title[record.language] ?? "")
            }
        } else {
            resultView(nil, title: "")
        }
    }

    private func resultView(_ record: SurveyRecord?, title: String) -> some View {
        let status = record.map(SurveyDisplayStatus.init)
        return VStack(alignment: .leading, spacing: Theme.Space.l) {
            switch status {
            case .submitted?:
                StatusLabel(kind: .success,
                            text: NSLocalizedString("survey_status_submitted", comment: ""))
                Text(NSLocalizedString("survey_thanks", comment: ""))
                    .foregroundStyle(Theme.textSecondary)
            case .savedWaitingForNetwork?:
                StatusLabel(kind: .warning,
                            text: NSLocalizedString("survey_status_saved_pending", comment: ""))
                Text(NSLocalizedString("survey_saved_pending_body", comment: ""))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .declined?:
                StatusLabel(kind: .neutral,
                            text: NSLocalizedString("survey_status_declined", comment: ""))
            case .notAccepted?:
                StatusLabel(kind: .warning,
                            text: NSLocalizedString("survey_status_not_accepted", comment: ""))
            default:
                Text(NSLocalizedString("survey_unavailable", comment: ""))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(spacing: Theme.Space.s) {
                if status == .savedWaitingForNetwork {
                    Button {
                        isRetrying = true
                        Task {
                            await ResearchUploader.shared.flush()
                            isRetrying = false
                        }
                    } label: {
                        HStack {
                            if isRetrying { ProgressView() }
                            Text(NSLocalizedString("common_retry", comment: ""))
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isRetrying)
                    .accessibilityIdentifier("survey.retryUpload")
                }
                Button(action: onClose) {
                    Text(NSLocalizedString("common_close", comment: ""))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("survey.close")
            }
        }
        .padding(Theme.pageMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("survey.result")
    }
}

/// 以 sheet 形式打开一份问卷。用于首页提示行、设置页入口。
struct ResearchSurveySheet: View {
    let formKey: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ResearchSurveyContent(formKey: formKey) { dismiss() }
        }
        .tint(Theme.primary)
    }
}

/// 使用后问卷的邀请。在用户**结束当前反馈之后**才出现，半屏、可下拉关掉
/// （下拉关掉 = 稍后填写，不是拒绝）。
struct PostSurveyInvitationSheet: View {
    let onFinish: () -> Void
    @State private var answering = false

    var body: some View {
        NavigationStack {
            if answering {
                ResearchSurveyContent(formKey: SurveyCenter.postKey, onClose: onFinish)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text(NSLocalizedString("survey_post_invite_title", comment: ""))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(NSLocalizedString("survey_post_invite_body", comment: ""))
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    SurveyInvitationButtons(
                        onStart: { answering = true },
                        onLater: {
                            SurveyCenter.deferSurvey(SurveyCenter.postKey)
                            onFinish()
                        },
                        onDecline: {
                            SurveyCenter.decline(SurveyCenter.postKey)
                            onFinish()
                        })
                }
                .padding(Theme.pageMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.background)
                .accessibilityElement(children: .contain)
        .accessibilityIdentifier("surveyInvite.post")
            }
        }
        .tint(Theme.primary)
    }
}
