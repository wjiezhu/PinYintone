import Foundation

enum RegisterError: LocalizedError {
    case emailAlreadyExists
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .emailAlreadyExists:
            return NSLocalizedString("error_email_already_exists", comment: "")
        case .networkError(let underlying):
            return underlying.localizedDescription
        }
    }
}
