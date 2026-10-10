import Foundation
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "UsernameService")

/// Service for managing usernames and @handles
@MainActor
class UsernameService: ObservableObject {
    static let shared = UsernameService()

    private let firebaseClient = FirebaseCallableClient.shared

    private init() {}

    // MARK: - Username Validation

    /// Validates username format locally
    /// Returns nil if valid, otherwise returns error message
    func validateUsernameFormat(_ username: String) -> String? {
        let normalizedUsername = username.lowercased().trimmingCharacters(in: .whitespaces)

        // Check length
        if normalizedUsername.count < 3 {
            return "Username must be at least 3 characters"
        }
        if normalizedUsername.count > 20 {
            return "Username must be 20 characters or less"
        }

        // Check format (alphanumeric + hyphen/underscore)
        let usernameRegex = "^[a-z0-9_-]+$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        if !predicate.evaluate(with: normalizedUsername) {
            return "Username can only contain lowercase letters, numbers, hyphens, and underscores"
        }

        // Check for reserved usernames
        let reservedUsernames = [
            "admin", "wickett", "support", "help", "api", "system",
            "official", "staff", "moderator", "root", "null", "undefined"
        ]
        if reservedUsernames.contains(normalizedUsername) {
            return "This username is reserved"
        }

        return nil
    }

    /// Normalizes username (lowercase, trim, remove @ prefix if present)
    func normalizeUsername(_ username: String) -> String {
        var normalized = username.trimmingCharacters(in: .whitespaces).lowercased()

        // Remove @ prefix if user typed it
        if normalized.hasPrefix("@") {
            normalized = String(normalized.dropFirst())
        }

        return normalized
    }

    // MARK: - Cloud Function Calls

    /// Check if username is available
    func checkAvailability(username: String) async throws -> (available: Bool, reason: String?) {
        let normalizedUsername = normalizeUsername(username)

        logger.info("🔍 Checking availability for username: \(normalizedUsername)")

        // First validate format locally
        if let formatError = validateUsernameFormat(normalizedUsername) {
            return (false, formatError)
        }

        let data: [String: Any] = [
            "username": normalizedUsername
        ]

        let result = try await firebaseClient.call("checkUsernameAvailability", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let available = responseData["available"] as? Bool else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to check availability"
            throw UsernameError.checkFailed(error)
        }

        let reason = responseData["reason"] as? String

        logger.info("\(available ? "✅ Username available" : "❌ Username taken") \(reason ?? "unknown")")

        return (available, reason)
    }

    /// Update user's username
    func updateUsername(username: String) async throws -> String {
        let normalizedUsername = normalizeUsername(username)

        logger.info("📝 Updating username to: \(normalizedUsername)")

        // Validate format locally first
        if let formatError = validateUsernameFormat(normalizedUsername) {
            throw UsernameError.invalidFormat(formatError)
        }

        let data: [String: Any] = [
            "username": normalizedUsername
        ]

        let result = try await firebaseClient.call("updateUsername", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let confirmedUsername = responseData["username"] as? String else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to update username"
            throw UsernameError.updateFailed(error)
        }

        logger.info("✅ Username updated to: \(confirmedUsername)")

        return confirmedUsername
    }
}

// MARK: - Errors

enum UsernameError: LocalizedError {
    case invalidFormat(String)
    case checkFailed(String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat(let message): return message
        case .checkFailed(let message): return "Failed to check availability: \(message)"
        case .updateFailed(let message): return "Failed to update username: \(message)"
        }
    }
}
