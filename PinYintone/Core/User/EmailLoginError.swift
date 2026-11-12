import Foundation

/// 邮箱验证码登录的失败原因。每一种都给一句能照着做的提示，不给系统原始报错。
///
/// 服务端的 `detail` 形如「email_code_invalid：验证码不对，还可以试 3 次」，
/// 冒号（全角）前是机器可读的原因码（见 backend/README.md 的错误码表）。
enum EmailLoginError: LocalizedError, Equatable {
    case invalidEmail
    case codeFormat
    case codeInvalid(attemptsLeft: Int?)
    case codeExpired
    case attemptsExceeded
    case cooldown(seconds: Int)
    case rateLimited
    /// 邮件服务没配好或暂时发不出去（503）：可以稍后再试，或先用 Apple 登录
    case unavailable
    case network
    case server

    init(status: Int, detail: String, retryAfter: Int?) {
        let code = detail.split(separator: "：", maxSplits: 1).first.map(String.init) ?? ""
        switch code {
        case "email_invalid":                self = .invalidEmail
        case "email_code_format":            self = .codeFormat
        case "email_code_invalid":           self = .codeInvalid(attemptsLeft: Self.number(in: detail))
        case "email_code_expired":           self = .codeExpired
        case "email_code_attempts_exceeded": self = .attemptsExceeded
        case "email_code_cooldown":          self = .cooldown(seconds: retryAfter ?? 60)
        case "email_code_rate_limited":      self = .rateLimited
        case "email_not_configured", "email_send_failed": self = .unavailable
        default:
            switch status {
            case 400, 422: self = .invalidEmail
            case 429:      self = .rateLimited
            case 503:      self = .unavailable
            default:       self = .server
            }
        }
    }

    /// 「还可以试 3 次」里的数字；没有就是 nil
    private static func number(in detail: String) -> Int? {
        guard let reason = detail.split(separator: "：", maxSplits: 1).last else { return nil }
        let digits = reason.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return NSLocalizedString("email_error_invalid_email", comment: "")
        case .codeFormat:
            return NSLocalizedString("email_error_code_format", comment: "")
        case .codeInvalid(let left?):
            return String(format: NSLocalizedString("email_error_code_invalid_left", comment: ""), left)
        case .codeInvalid(nil):
            return NSLocalizedString("email_error_code_invalid", comment: "")
        case .codeExpired:
            return NSLocalizedString("email_error_code_expired", comment: "")
        case .attemptsExceeded:
            return NSLocalizedString("email_error_attempts", comment: "")
        case .cooldown(let seconds):
            return String(format: NSLocalizedString("email_error_cooldown", comment: ""), seconds)
        case .rateLimited:
            return NSLocalizedString("email_error_rate_limited", comment: "")
        case .unavailable:
            return NSLocalizedString("email_error_unavailable", comment: "")
        case .network, .server:
            return NSLocalizedString("email_error_network", comment: "")
        }
    }
}
