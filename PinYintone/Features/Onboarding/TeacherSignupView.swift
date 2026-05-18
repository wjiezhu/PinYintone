import SwiftUI

/// 教师注册：邮箱 + 密码 + 姓名 → 服务器返回 6 位班级码
struct TeacherSignupView: View {
    @EnvironmentObject var userManager: UserManager

    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var generatedClassCode: String?

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
        .navigationTitle(NSLocalizedString("role_teacher", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .sheet(item: Binding(
            get: { generatedClassCode.map { ClassCodeResult(code: $0) } },
            set: { _ in }   // 不允许手动关闭
        )) { result in
            classCodeRevealSheet(code: result.code)
                .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Sub-views

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.badge.shield.checkmark.fill")
                .font(.system(size: 44))
                .foregroundStyle(.purple)
            Text(NSLocalizedString("teacher_signup_subtitle", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            field(label: NSLocalizedString("teacher_signup_name", comment: ""),
                  icon: "person", text: $name,
                  contentType: .name, keyboard: .default)

            field(label: NSLocalizedString("teacher_signup_email", comment: ""),
                  icon: "envelope", text: $email,
                  contentType: .emailAddress, keyboard: .emailAddress)

            secureField(label: NSLocalizedString("teacher_signup_password", comment: ""),
                        icon: "lock", text: $password)
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
        Button { submit() } label: {
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
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(isLoading || name.isEmpty || email.isEmpty || password.isEmpty)
    }

    // MARK: - Class code reveal sheet

    private func classCodeRevealSheet(code: String) -> some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(NSLocalizedString("teacher_classcode_title", comment: ""))
                .font(.title.bold())
            VStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text(NSLocalizedString("teacher_classcode_body", comment: ""))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            ShareLink(item: String(format: NSLocalizedString("teacher_classcode_share", comment: ""), code)) {
                Label(NSLocalizedString("teacher_classcode_share_btn", comment: ""), systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            Button(NSLocalizedString("teacher_classcode_go_dashboard", comment: "")) {
                // ContentView 检测到 profile.role == .teacher 后自动切换到 TeacherDashboardView
                generatedClassCode = nil
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func field(
        label: String, icon: String, text: Binding<String>,
        contentType: UITextContentType, keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(label, text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func secureField(label: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField(label, text: text)
                .textContentType(.newPassword)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func submit() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let code = try await userManager.registerTeacher(
                    email: email, password: password, name: name)
                generatedClassCode = code
            } catch let e as RegisterError {
                errorMessage = e.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Identifiable wrapper for sheet binding
private struct ClassCodeResult: Identifiable {
    let id = UUID()
    let code: String
}
