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
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                headerSection
                formSection
                errorLabel
                submitButton
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("role_teacher", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .sheet(item: Binding(
            get: { generatedClassCode.map { ClassCodeResult(code: $0) } },
            set: { _ in }   // 不允许手动关闭
        ), onDismiss: { userManager.finishTeacherRegistration() }) { result in
            classCodeRevealSheet(code: result.code)
                .interactiveDismissDisabled(true)
        }
    }

    // MARK: - Sub-views

    private var headerSection: some View {
        Text(NSLocalizedString("teacher_signup_subtitle", comment: ""))
            .font(.body)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
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
            StatusLabel(kind: .warning, text: msg)
        }
    }

    private var submitButton: some View {
        Button { submit() } label: {
            if isLoading {
                ProgressView()
            } else {
                Text(NSLocalizedString("signup_submit", comment: ""))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading || name.isEmpty || email.isEmpty || password.isEmpty)
    }

    // MARK: - Class code reveal sheet

    private func classCodeRevealSheet(code: String) -> some View {
        VStack(spacing: 32) {
            Spacer()
            IconTile(systemName: "checkmark", size: 64)
            Text(NSLocalizedString("teacher_classcode_title", comment: ""))
                .font(.title.bold())
            VStack(spacing: 8) {
                Text(code)
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.primary)
                Text(NSLocalizedString("teacher_classcode_body", comment: ""))
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            ShareLink(item: String(format: NSLocalizedString("teacher_classcode_share", comment: ""), code)) {
                Label(NSLocalizedString("teacher_classcode_share_btn", comment: ""), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, Theme.pageMargin)
            Button(NSLocalizedString("teacher_classcode_go_dashboard", comment: "")) {
                // 关闭后 onDismiss 才发布 profile，ContentView 随之切到主界面View
                generatedClassCode = nil
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, Theme.pageMargin)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: - Helpers

    private func field(
        label: String, icon: String, text: Binding<String>,
        contentType: UITextContentType, keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            TextField(label, text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(minHeight: Theme.minTap)
                .surfaceCard(padding: Theme.Space.m)
        }
    }

    private func secureField(label: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
            SecureField(label, text: text)
                .textContentType(.newPassword)
                .frame(minHeight: Theme.minTap)
                .surfaceCard(padding: Theme.Space.m)
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
    var id: String { code }     // 每次取值都不变，否则页面一刷新弹层就重开
    let code: String
}
