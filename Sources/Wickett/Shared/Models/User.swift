import Foundation

/// User model representing an authenticated user
struct User: Identifiable, Codable {
    let id: String
    let email: String?
    let name: String?
    let walletAddress: String?
    let username: String?

    var displayName: String {
        name ?? email ?? "User"
    }

    var shortWalletAddress: String? {
        guard let wallet = walletAddress else { return nil }
        return String(wallet.prefix(6)) + "..." + String(wallet.suffix(4))
    }

    /// Returns the @handle for this user, or empty string if no username
    var handle: String {
        guard let username = username else { return "" }
        return "@\(username)"
    }

    /// Returns a short version of the handle for compact display
    var shortHandle: String? {
        username
    }
}
