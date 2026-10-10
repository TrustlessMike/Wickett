import Foundation

/// Authentication errors
enum AuthError: LocalizedError {
    case invalidCredential
    case missingToken
    case authenticationFailed(String)
    case networkError(String)
    case serviceNotInitialized
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid credentials provided"
        case .missingToken:
            return "Missing authentication token"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serviceNotInitialized:
            return "Authentication service not initialized"
        case .userCancelled:
            return "Authentication cancelled by user"
        }
    }
}
