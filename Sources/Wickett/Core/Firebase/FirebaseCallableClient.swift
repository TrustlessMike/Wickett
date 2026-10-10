import Foundation
import FirebaseFunctions
import FirebaseAuth

/// Wrapper around Firebase Callable Functions with automatic idToken injection and retry logic
@MainActor
class FirebaseCallableClient {
    static let shared = FirebaseCallableClient()

    private let functions: Functions

    private init() {
        functions = Functions.functions()
    }

    /// Calls a Firebase Callable Function with automatic idToken injection and retry/backoff on transient errors
    func call(
        _ name: String,
        data: [String: Any],
        timeout: TimeInterval = 45,
        retries: Int = 3
    ) async throws -> HTTPSCallableResult {
        var attempt = 0
        var lastError: Error?

        while attempt <= retries {
            do {
                let callable = functions.httpsCallable(name)
                callable.timeoutInterval = timeout
                // Call directly without adding idToken - let Firebase SDK handle authentication
                return try await callable.call(data)
            } catch let error as NSError {
                lastError = error

                // Check if error is retryable
                if isRetryableError(error) && attempt < retries {
                    let backoffDelay = calculateBackoff(attempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))
                    attempt += 1
                    continue
                } else {
                    throw error
                }
            }
        }

        throw lastError ?? FirebaseCallableError.unknownError
    }

    private func isRetryableError(_ error: NSError) -> Bool {
        // Retry on network errors, timeouts, and server errors
        let retryableCodes = [
            FunctionsErrorCode.unavailable.rawValue,
            FunctionsErrorCode.deadlineExceeded.rawValue,
            FunctionsErrorCode.internal.rawValue
        ]

        return retryableCodes.contains(error.code)
    }

    private func calculateBackoff(attempt: Int) -> TimeInterval {
        // Exponential backoff: 1s, 2s, 4s, 8s, etc.
        return min(pow(2.0, Double(attempt)), 10.0)
    }
}

enum FirebaseCallableError: LocalizedError {
    case unknownError

    var errorDescription: String? {
        switch self {
        case .unknownError:
            return "An unknown error occurred while calling Firebase function"
        }
    }
}
