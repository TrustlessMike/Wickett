import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    private let db = Firestore.firestore()

    private init() {
        setupFirebase()
    }

    private func setupFirebase() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    // MARK: - Firebase Bridge: Sync Privy Users to Firestore

    func syncPrivyUserToFirestore(privyUser: User) async throws {
        let privyUserId = privyUser.id

        let userData: [String: Any] = [
            "privyId": privyUserId,
            "email": privyUser.email ?? "",
            "displayName": privyUser.name ?? "",
            "walletAddress": privyUser.walletAddress ?? "",
            "createdAt": FieldValue.serverTimestamp(),
            "lastSignIn": FieldValue.serverTimestamp(),
            "authProvider": "privy-apple"
        ]

        try await db.collection("users").document(privyUserId).setData(userData, merge: true)
    }

    func getUserData(privyId: String) async throws -> [String: Any]? {
        let document = try await db.collection("users").document(privyId).getDocument()
        return document.data()
    }

    func updateUserLastSignIn(privyId: String) async throws {
        try await db.collection("users").document(privyId).updateData([
            "lastSignIn": FieldValue.serverTimestamp()
        ])
    }
}

// MARK: - Errors

enum FirebaseAuthError: LocalizedError {
    case invalidCredential
    case missingToken
    case userNotFound
    case authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential"
        case .missingToken:
            return "Missing identity token"
        case .userNotFound:
            return "User not found"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        }
    }
}
