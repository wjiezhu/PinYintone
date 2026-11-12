import XCTest
@testable import PinYintone

/// 邮箱验证码登录（学生）：原因码解析、补送档案的请求体、账号隔离。
/// 真正收发验证码的全流程在界面测试 `ModuleSmokeUITests.testEmailCodeSignIn` 里对本地后端跑。
@MainActor
final class EmailLoginTests: XCTestCase {

    private func profile(apple: String? = nil, email: String? = nil) -> UserProfile {
        UserProfile(deviceID: "dev-1", role: .student, appleUserID: apple, nickname: "Amina",
                    classCode: nil, teacherEmail: nil, teacherToken: nil, nativeLanguage: "fr",
                    spokenLanguages: ["fr"], registeredAt: Date(), loginEmail: email)
    }

    // MARK: - 服务端原因码 → 能照着做的提示

    func testServerReasonCodesMapToActionableErrors() {
        XCTAssertEqual(EmailLoginError(status: 400, detail: "email_invalid：邮箱格式不对", retryAfter: nil),
                       .invalidEmail)
        XCTAssertEqual(EmailLoginError(status: 400, detail: "email_code_format：验证码是 6 位数字",
                                       retryAfter: nil), .codeFormat)
        XCTAssertEqual(EmailLoginError(status: 401, detail: "email_code_invalid：验证码不对，还可以试 3 次",
                                       retryAfter: nil), .codeInvalid(attemptsLeft: 3))
        XCTAssertEqual(EmailLoginError(status: 401, detail: "email_code_invalid：验证码不对或已失效，请重新获取",
                                       retryAfter: nil), .codeInvalid(attemptsLeft: nil))
        XCTAssertEqual(EmailLoginError(status: 401, detail: "email_code_expired：验证码已过期，请重新获取",
                                       retryAfter: nil), .codeExpired)
        XCTAssertEqual(EmailLoginError(status: 401, detail: "email_code_attempts_exceeded：尝试次数太多",
                                       retryAfter: nil), .attemptsExceeded)
        XCTAssertEqual(EmailLoginError(status: 429, detail: "email_code_cooldown：请 42 秒后再获取",
                                       retryAfter: 42), .cooldown(seconds: 42))
        XCTAssertEqual(EmailLoginError(status: 429, detail: "email_code_rate_limited：请一小时后再试",
                                       retryAfter: 3600), .rateLimited)
        XCTAssertEqual(EmailLoginError(status: 503, detail: "email_not_configured：邮件服务未配置",
                                       retryAfter: nil), .unavailable)
        XCTAssertEqual(EmailLoginError(status: 503, detail: "email_send_failed：暂时发不出去",
                                       retryAfter: nil), .unavailable)
        // 认不出的原因码按状态码兜底，不会崩、不会显示原始报错
        XCTAssertEqual(EmailLoginError(status: 503, detail: "", retryAfter: nil), .unavailable)
        XCTAssertEqual(EmailLoginError(status: 500, detail: "boom", retryAfter: nil), .server)
    }

    func testEveryErrorHasATranslatedMessage() {
        let all: [EmailLoginError] = [.invalidEmail, .codeFormat, .codeInvalid(attemptsLeft: 2),
                                      .codeInvalid(attemptsLeft: nil), .codeExpired, .attemptsExceeded,
                                      .cooldown(seconds: 30), .rateLimited, .unavailable, .network, .server]
        for e in all {
            let text = e.errorDescription ?? ""
            XCTAssertFalse(text.isEmpty, "\(e)")
            XCTAssertFalse(text.hasPrefix("email_error_"), "\(e) 显示成了键名")
        }
        XCTAssertTrue(EmailLoginError.codeInvalid(attemptsLeft: 2).errorDescription!.contains("2"))
        XCTAssertTrue(EmailLoginError.cooldown(seconds: 30).errorDescription!.contains("30"))
    }

    // MARK: - 补送档案

    /// 邮箱账号补送时写 provider = email、不带凭证，邮箱本身不上传
    func testEmailAccountReRegistersAsEmailProviderWithoutTheAddress() throws {
        let p = profile(email: "amina@gmail.com")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            APIClient.StudentRegistrationBody(profile: p, identityToken: nil))) as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, "email")
        XCTAssertEqual(json["deviceID"] as? String, "dev-1")
        XCTAssertNil(json["loginEmail"], "邮箱不随补送上传")
        XCTAssertNil(json["identityToken"])
        XCTAssertNil(json["appleUserID"])
    }

    func testAppleAccountBodyIsUnchanged() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            APIClient.StudentRegistrationBody(profile: profile(apple: "apple-1"), identityToken: nil)))
            as? [String: Any])
        XCTAssertEqual(json["provider"] as? String, "apple")
        XCTAssertNil(json["loginEmail"])
    }

    // MARK: - 账号隔离

    /// Apple 与邮箱是不同账号，研究状态各存各的；邮箱大小写不同仍是同一账号
    func testAccountKeysSeparateAppleAndEmailAccounts() {
        XCTAssertEqual(profile(apple: "apple-1").accountKey, "apple-1")
        XCTAssertEqual(profile(email: "amina@gmail.com").accountKey, "email:amina@gmail.com")
        XCTAssertNotEqual(profile(apple: "amina@gmail.com").accountKey,
                          profile(email: "amina@gmail.com").accountKey)
        XCTAssertEqual(UserManager.normalizedEmail("  Amina@Gmail.COM "), "amina@gmail.com")
    }

    /// 升级前存下的档案没有 loginEmail 字段，照样读得出来
    func testOldSavedProfilesStillDecode() throws {
        let old = """
        {"deviceID":"dev-1","role":"student","appleUserID":"apple-1","registeredAt":0}
        """
        let p = try JSONDecoder().decode(UserProfile.self, from: Data(old.utf8))
        XCTAssertNil(p.loginEmail)
        XCTAssertEqual(p.accountKey, "apple-1")
    }
}
