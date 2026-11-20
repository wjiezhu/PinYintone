import AuthenticationServices
import SwiftUI

/// 学生注册：Sign in with Apple，或邮箱验证码（`EmailLoginView`）。
/// - 名字可选：Apple 首次授权会返回 fullName，自动作为昵称；也可手动输入覆盖
/// - 分组由后端均衡随机分配；同一 Apple ID 跨设备登录继承原分组（幂等）
struct StudentSignupView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var nickname = ""
    /// 选中的 ISO 639 代码（含 `other`）
    @State private var selectedLanguages: Set<String> = []
    @State private var showLanguagePicker = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(NSLocalizedString("student_signup_subtitle", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                formSection
                languagesSection
                errorLabel
                appleButton
                emailButton
                #if DEBUG
                uiTestLoginButton
                #endif
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("role_student", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .overlay { if isLoading { ProgressView() } }
        .sheet(isPresented: $showLanguagePicker) {
            CodeListPickerSheet(source: SpokenLanguage.listSource, kind: .language,
                                language: LocalizationManager.shared.language,
                                overrides: SpokenLanguage.presetNames,
                                selected: selectedLanguages,
                                title: NSLocalizedString("signup_languages_search", comment: "")) { code in
                toggleLanguage(code)
            }
        }
    }

    // MARK: - Sub-views

    private var formSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            fieldLabel("signup_nickname_label")
            TextField(NSLocalizedString("signup_nickname_hint", comment: ""), text: $nickname)
                .textContentType(.name)
                .submitLabel(.done)
                .frame(minHeight: Theme.minTap)
                .surfaceCard(padding: Theme.Space.m)
        }
    }

    private func fieldLabel(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 会说的语言（多选，母语迁移分析用）。常见的几种直接列出，其余从 ISO 639 完整列表里搜
    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            fieldLabel("signup_languages_label")
            // 自适应换行的多选标签
            FlowLayout(spacing: Theme.Space.s) {
                ForEach(SpokenLanguage.presets) { preset in
                    languageChip(code: preset.code,
                                 name: NSLocalizedString(preset.localizationKey, comment: ""))
                }
                // 从完整列表里选的，跟在预置项后面，点一下取消
                ForEach(extraLanguages, id: \.self) { code in
                    languageChip(code: code, name: languageName(code))
                }
            }
            Button {
                showLanguagePicker = true
            } label: {
                Label(NSLocalizedString("signup_languages_search", comment: ""), systemImage: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("signup.languageSearch")
        }
    }

    /// 不在预置项里、由学习者从完整列表里选的代码，按显示名排
    private var extraLanguages: [String] {
        let preset = Set(SpokenLanguage.presets.map(\.code))
        return selectedLanguages.filter { !preset.contains($0) }
            .sorted { languageName($0).localizedStandardCompare(languageName($1)) == .orderedAscending }
    }

    private func languageName(_ code: String) -> String {
        SpokenLanguage.name(for: code, language: LocalizationManager.shared.language)
    }

    private func toggleLanguage(_ code: String) {
        if selectedLanguages.contains(code) { selectedLanguages.remove(code) }
        else { selectedLanguages.insert(code) }
    }

    /// 多选标签：选中用描边 + 对勾表示，不单靠颜色。不放国旗——语言不等于国家。
    private func languageChip(code: String, name: String) -> some View {
        let selected = selectedLanguages.contains(code)
        return Button {
            toggleLanguage(code)
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(name)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? Theme.primary : Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.minTap)
            .background(selected ? Theme.primary.opacity(0.10) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(selected ? Theme.primary : Theme.border,
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("signup.language.\(code)")
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let msg = errorMessage {
            StatusLabel(kind: .warning, text: msg)
        }
    }

    private var appleButton: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    /// 没有 Apple 账号、或想用 Gmail 等邮箱的学习者：邮箱验证码登录。
    /// 名字与会说的语言沿用本页已填的内容。
    private var emailButton: some View {
        NavigationLink {
            let typed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            EmailLoginView(nickname: typed.isEmpty ? nil : typed,
                           languages: selectedLanguages.sorted())
        } label: {
            Label(NSLocalizedString("signup_email_option", comment: ""), systemImage: "envelope")
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier("signup.emailLogin")
    }

    #if DEBUG
    /// 仅开发构建、且启动时带了 `PT_UITEST_LOGIN` 才出现：界面测试用它建立账号，
    /// 因为 Sign in with Apple 没法在无人值守的模拟器里完成。正式构建里不存在。
    @ViewBuilder
    private var uiTestLoginButton: some View {
        if let identifier = UITestSupport.loginIdentifier {
            Button("UI test sign-in") {
                submit(appleUserID: identifier, identityToken: nil, nickname: nil, languages: [])
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("signup.uiTestLogin")
        }
    }
    #endif

    // MARK: - Actions

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = NSLocalizedString("signup_apple_failed", comment: "")
                return
            }
            // Apple 仅在首次授权返回 fullName；手动输入优先，其次 Apple 名字
            let appleName = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            let typed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = typed.isEmpty ? (appleName.isEmpty ? nil : appleName) : typed
            // 服务端用它验签确认 Apple 账号（只信客户端传的 cred.user 会被冒充）。
            // 拿不到时照旧登录：过渡期服务端仍放行，之后由服务端决定
            let token = cred.identityToken.flatMap { String(data: $0, encoding: .utf8) }
            submit(appleUserID: cred.user, identityToken: token, nickname: finalName,
                   languages: selectedLanguages.sorted())

        case .failure(let error):
            // 用户主动取消不算错误：停在本页，登录按钮仍在，可重试，也可返回上一步
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            // 其它失败给一句看得懂、说明下一步的话，而不是系统的原始报错
            errorMessage = NSLocalizedString("signup_apple_failed", comment: "")
        }
    }

    private func submit(appleUserID: String, identityToken: String?, nickname: String?,
                        languages: [String]) {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.registerStudent(
                    appleUserID: appleUserID, identityToken: identityToken, nickname: nickname,
                    spokenLanguages: languages)
            } catch let e as RegisterError {
                errorMessage = e.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
