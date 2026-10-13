import AuthenticationServices
import SwiftUI

/// 学生注册：Sign in with Apple。
/// - 名字可选：Apple 首次授权会返回 fullName，自动作为昵称；也可手动输入覆盖
/// - 分组由后端均衡随机分配；同一 Apple ID 跨设备登录继承原分组（幂等）
struct StudentSignupView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var nickname = ""
    @State private var selectedLanguages: Set<SpokenLanguage> = []
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

    /// 会说的语言（多选，母语迁移分析用）
    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            fieldLabel("signup_languages_label")
            // 自适应换行的多选标签
            FlowLayout(spacing: Theme.Space.s) {
                ForEach(SpokenLanguage.displayOrder) { lang in
                    languageChip(lang)
                }
            }
        }
    }

    /// 多选标签：选中用描边 + 对勾表示，不单靠颜色。不放国旗——语言不等于国家。
    private func languageChip(_ lang: SpokenLanguage) -> some View {
        let selected = selectedLanguages.contains(lang)
        return Button {
            if selected { selectedLanguages.remove(lang) }
            else { selectedLanguages.insert(lang) }
        } label: {
            HStack(spacing: Theme.Space.xs) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(NSLocalizedString(lang.localizationKey, comment: ""))
                    .font(.subheadline.weight(selected ? .semibold : .regular))
            }
            .foregroundStyle(selected ? Theme.accent : Theme.textPrimary)
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: Theme.minTap)
            .background(selected ? Theme.accent.opacity(0.10) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(selected ? Theme.accent : Theme.divider,
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    #if DEBUG
    /// 仅开发构建、且启动时带了 `PT_UITEST_LOGIN` 才出现：界面测试用它建立账号，
    /// 因为 Sign in with Apple 没法在无人值守的模拟器里完成。正式构建里不存在。
    @ViewBuilder
    private var uiTestLoginButton: some View {
        if let identifier = UITestSupport.loginIdentifier {
            Button("UI test sign-in") {
                submit(appleUserID: identifier, nickname: nil, languages: [])
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
            submit(appleUserID: cred.user, nickname: finalName,
                   languages: Array(selectedLanguages))

        case .failure(let error):
            // 用户主动取消不算错误：停在本页，登录按钮仍在，可重试，也可返回上一步
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            // 其它失败给一句看得懂、说明下一步的话，而不是系统的原始报错
            errorMessage = NSLocalizedString("signup_apple_failed", comment: "")
        }
    }

    private func submit(appleUserID: String, nickname: String?,
                        languages: [SpokenLanguage]) {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.registerStudent(
                    appleUserID: appleUserID, nickname: nickname,
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
