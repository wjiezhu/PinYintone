import Combine
import SwiftUI

/// 学生用邮箱验证码登录：输入邮箱 → 收 6 位验证码 → 登录。
/// 任何邮箱都可以（Gmail、QQ 邮箱等）；第一次登录即建账号。
///
/// 和 Apple 登录是**不同的账号**：同一个人先后用两种方式登录，会是两位研究参与者。
/// 名字与会说的语言沿用上一页（学生注册页）已填的内容。
struct EmailLoginView: View {
    @EnvironmentObject var userManager: UserManager

    let nickname: String?
    let languages: [SpokenLanguage]

    @State private var email = ""
    @State private var code = ""
    /// 验证码已发到的邮箱（规范化后）。邮箱改了就回到「发送验证码」
    @State private var sentTo: String?
    @State private var resendAt: Date?
    @State private var validMinutes = 10
    @State private var now = Date()
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 当前输入的邮箱已经收到验证码，可以填码登录
    private var codeStage: Bool {
        sentTo != nil && sentTo == UserManager.normalizedEmail(email)
    }

    private var resendWait: Int {
        guard let resendAt else { return 0 }
        return max(0, Int(resendAt.timeIntervalSince(now).rounded(.up)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                Text(NSLocalizedString("email_login_body", comment: ""))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                emailField
                if codeStage { codeSection }
                if let errorMessage {
                    StatusLabel(kind: .warning, text: errorMessage)
                        .accessibilityIdentifier("emailLogin.error")
                }
                primaryButton
            }
            .padding(.horizontal, Theme.pageMargin)
            .padding(.vertical, Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.background)
        .navigationTitle(NSLocalizedString("email_login_title", comment: ""))
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .overlay { if isLoading { ProgressView() } }
        .onReceive(ticker) { now = $0 }
        .onAppear { focus = .email }
    }

    // MARK: - Sub-views

    private func fieldLabel(_ key: String) -> some View {
        Text(NSLocalizedString(key, comment: ""))
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            fieldLabel("email_login_email_label")
            TextField("name@gmail.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.send)
                .onSubmit { if !codeStage { sendCode() } }
                .focused($focus, equals: .email)
                .frame(minHeight: Theme.minTap)
                .surfaceCard(padding: Theme.Space.m)
                .accessibilityIdentifier("emailLogin.email")
        }
    }

    private var codeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            StatusLabel(kind: .success,
                        text: String(format: NSLocalizedString("email_login_sent", comment: ""),
                                     sentTo ?? "", validMinutes))
                .accessibilityIdentifier("emailLogin.sent")
            fieldLabel("email_login_code_label")
            TextField("123456", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .focused($focus, equals: .code)
                .frame(minHeight: Theme.minTap)
                .surfaceCard(padding: Theme.Space.m)
                .accessibilityIdentifier("emailLogin.code")
                // 只留数字、最多 6 位（单参数写法：iOS 16 上要能跑，见禁令 28）
                .onChange(of: code) { newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if digits != newValue { code = digits }
                }
            Button {
                sendCode()
            } label: {
                Text(resendWait > 0
                     ? String(format: NSLocalizedString("email_login_resend_wait", comment: ""),
                              resendWait)
                     : NSLocalizedString("email_login_resend", comment: ""))
                    .frame(minHeight: Theme.minTap)
            }
            .disabled(resendWait > 0)
            .accessibilityIdentifier("emailLogin.resend")
        }
    }

    private var primaryButton: some View {
        Button {
            codeStage ? submit() : sendCode()
        } label: {
            Text(NSLocalizedString(codeStage ? "email_login_submit" : "email_login_send",
                                   comment: ""))
                .frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(codeStage ? code.count != 6
                            : email.trimmingCharacters(in: .whitespaces).isEmpty)
        .accessibilityIdentifier(codeStage ? "emailLogin.submit" : "emailLogin.send")
    }

    // MARK: - Actions

    private func sendCode() {
        let target = UserManager.normalizedEmail(email)
        guard !target.isEmpty else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                let sent = try await userManager.requestEmailCode(email: target)
                sentTo = target
                code = ""
                resendAt = Date().addingTimeInterval(TimeInterval(sent.resendAfterSeconds))
                validMinutes = max(1, sent.expiresInSeconds / 60)
                focus = .code
            } catch let e as EmailLoginError {
                if case .cooldown(let seconds) = e, sentTo == target {
                    // 已经发过：留在填码这一步，只是暂时不能重发
                    resendAt = Date().addingTimeInterval(TimeInterval(seconds))
                }
                errorMessage = e.errorDescription
            } catch {
                errorMessage = EmailLoginError.network.errorDescription
            }
            isLoading = false
        }
    }

    private func submit() {
        guard let target = sentTo, code.count == 6 else { return }
        errorMessage = nil
        isLoading = true
        Task {
            do {
                try await userManager.registerStudentWithEmail(
                    email: target, code: code, nickname: nickname, spokenLanguages: languages)
                // 成功后 profile 已发布，ContentView 自动切到首页
            } catch let e as EmailLoginError {
                errorMessage = e.errorDescription
                // 验证码作废了：清空输入，提示重新获取
                switch e {
                case .codeExpired, .attemptsExceeded:
                    code = ""
                    resendAt = nil
                default:
                    break
                }
            } catch {
                errorMessage = EmailLoginError.network.errorDescription
            }
            isLoading = false
        }
    }
}
