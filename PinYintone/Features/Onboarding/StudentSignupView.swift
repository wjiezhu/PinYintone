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
            VStack(spacing: 28) {
                headerSection
                formSection
                languagesSection
                errorLabel
                appleButton
            }
            .padding(24)
        }
        .navigationTitle(NSLocalizedString("role_student", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .overlay { if isLoading { ProgressView() } }
    }

    // MARK: - Sub-views

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text(NSLocalizedString("student_signup_subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(NSLocalizedString("signup_nickname_label", comment: ""), systemImage: "person")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(NSLocalizedString("signup_nickname_hint", comment: ""), text: $nickname)
                .textContentType(.name)
                .submitLabel(.done)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    /// 会说的语言（多选，母语迁移分析用）
    private var languagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(NSLocalizedString("signup_languages_label", comment: ""),
                  systemImage: "globe")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 自适应换行的多选标签
            FlowLayout(spacing: 10) {
                ForEach(SpokenLanguage.displayOrder) { lang in
                    languageChip(lang)
                }
            }
        }
    }

    private func languageChip(_ lang: SpokenLanguage) -> some View {
        let selected = selectedLanguages.contains(lang)
        return Button {
            if selected { selectedLanguages.remove(lang) }
            else { selectedLanguages.insert(lang) }
        } label: {
            HStack(spacing: 6) {
                Text(lang.flag)
                Text(NSLocalizedString(lang.localizationKey, comment: ""))
                    .font(.subheadline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? Color.accentColor : Color(.secondarySystemBackground))
            .foregroundStyle(selected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var errorLabel: some View {
        if let msg = errorMessage {
            Text(msg)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
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
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

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
            // 用户主动取消不算错误，不打扰
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            errorMessage = error.localizedDescription
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
