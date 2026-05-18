import Foundation

enum RegisterError: LocalizedError {
    case invalidClassCode
    case emailAlreadyExists
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidClassCode:
            return NSLocalizedString("error_invalid_class_code", comment: "")
        case .emailAlreadyExists:
            return NSLocalizedString("error_email_already_exists", comment: "")
        case .networkError(let underlying):
            return underlying.localizedDescription
        }
    }
}
