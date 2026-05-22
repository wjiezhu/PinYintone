import SwiftUI

/// 学生注册：填名字即可（分组由后端均衡随机分配，无需测试码）。
struct StudentSignupView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// 必填校验：名字非空
    private var isNameValid: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                headerSection
                formSection
                errorLabel
                submitButton
            }
            .padding(24)
        }
        .navigationTitle(NSLocalizedString("role_student", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
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

    @ViewBuilder
    private var errorLabel: some View {
        if let msg = errorMessage {
            Text(msg)
                .font(.callout)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(NSLocalizedString("signup_submit", comment: ""))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isNameValid ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading || !isNameValid)
    }

    // MARK: - Actions

    private func submit() {
        guard isNameValid else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.registerStudent(
                    nickname: nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            } catch let e as RegisterError {
                errorMessage = e.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
