import SwiftUI

/// 学生注册：昵称（可选）+ 测试码（必填，决定 A/B 分组）
struct StudentSignupView: View {
    @EnvironmentObject var userManager: UserManager
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var classCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// 必填校验：6 位纯数字
    private var isCodeValid: Bool {
        classCode.count == 6 && classCode.allSatisfy(\.isNumber)
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
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("signup_nickname_label", comment: ""), systemImage: "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("signup_nickname_hint", comment: ""), text: $nickname)
                    .textContentType(.nickname)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(NSLocalizedString("signup_classcode_label", comment: ""), systemImage: "number")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(NSLocalizedString("signup_classcode_hint", comment: ""), text: $classCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: classCode) { _, new in
                        if new.count > 6 { classCode = String(new.prefix(6)) }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text(NSLocalizedString("signup_classcode_footer", comment: ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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
            .background(isCodeValid ? Color.accentColor : Color.gray.opacity(0.4))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading || !isCodeValid)
    }

    // MARK: - Actions

    private func submit() {
        guard isCodeValid else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.registerStudent(
                    nickname: nickname.isEmpty ? nil : nickname,
                    classCode: classCode
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
