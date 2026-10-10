import Foundation

/// Protocol defining authentication service capabilities
@MainActor
protocol AuthenticationService: ObservableObject {
    /// Current authentication state
    var isAuthenticated: Bool { get }

    /// Currently authenticated user
    var currentUser: User? { get }

    /// Wallet address for the authenticated user
    var walletAddress: String? { get }

    /// Authenticate with Apple Sign-In
    func authenticateWithApple() async throws

    /// Authenticate with Google Sign-In
    func authenticateWithGoogle() async throws

    /// Sign out the current user
    func signOut() async throws

    /// Check if user is authenticated
    func isUserAuthenticated() async -> Bool
}
