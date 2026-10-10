import Foundation
import AuthenticationServices
import Combine
import FirebaseFirestore
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "AuthCoordinator")

@MainActor
class AuthCoordinator: ObservableObject {
    static let shared = AuthCoordinator()

    private let hybridPrivyService = HybridPrivyService.shared
    private let db = Firestore.firestore()

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentUser: User?

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupObservers()
    }

    private func setupObservers() {
        // Observe HybridPrivyService auth state
        hybridPrivyService.$isAuthenticated
            .sink { [weak self] authenticated in
                self?.isAuthenticated = authenticated
            }
            .store(in: &cancellables)

        hybridPrivyService.$currentUser
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }

    // MARK: - Sign In with Privy OAuth (Apple)

    func signInWithPrivyOAuth() async throws {
        isLoading = true
        errorMessage = nil

        do {
            // HybridPrivyService handles:
            // 1. Privy OAuth authentication
            // 2. Firebase custom token creation
            // 3. Firebase sign-in
            // 4. User data sync
            try await hybridPrivyService.authenticateWithPrivyOAuth()

            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In with Privy OAuth (Google)

    func signInWithPrivyGoogle() async throws {
        isLoading = true
        errorMessage = nil

        do {
            try await hybridPrivyService.authenticateWithPrivyGoogle()
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        isLoading = true
        errorMessage = nil

        do {
            // Sign out from both Privy and Firebase
            try await hybridPrivyService.signOut()

            // Clear portfolio history for this session
            PortfolioHistoryManager.shared.clearHistory()

            currentUser = nil
            isAuthenticated = false
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Check Authentication Status

    func checkAuthenticationStatus() async {
        logger.info("🔎 Checking authentication status...")
        let authenticated = await hybridPrivyService.isUserAuthenticated()
        logger.info("🔎 Authenticated: \(authenticated)")

        await MainActor.run {
            self.isAuthenticated = authenticated

            // If authenticated, restore user from HybridPrivyService
            if authenticated {
                self.currentUser = hybridPrivyService.currentUser
                logger.info("🔎 Restored currentUser: \(String(describing: self.currentUser?.id))")
            }
        }

        // Fetch displayName from Firestore if authenticated
        if authenticated, let userId = currentUser?.id {
            logger.info("🔎 About to fetch displayName for userId: \(userId)")
            await fetchDisplayName(userId: userId)
        } else {
            logger.warning("⚠️ Not fetching displayName - authenticated: \(authenticated), currentUser.id: \(String(describing: self.currentUser?.id))")
        }
    }

    // MARK: - Fetch Display Name

    private func fetchDisplayName(userId: String) async {
        logger.info("🔍 Attempting to fetch displayName for userId: \(userId)")

        do {
            let document = try await db.collection("users").document(userId).getDocument()

            logger.info("📄 Document exists: \(document.exists)")

            if document.exists, let data = document.data() {
                logger.info("📦 Document data: \(data)")

                if let displayName = data["displayName"] as? String, !displayName.isEmpty {
                    logger.info("✅ Fetched displayName from Firestore: \(displayName)")

                    // Update current user with displayName
                    await MainActor.run {
                        if let user = self.currentUser {
                            self.currentUser = User(
                                id: user.id,
                                email: user.email,
                                name: displayName,
                                walletAddress: user.walletAddress,
                                username: user.username
                            )
                            logger.info("✅ Updated currentUser.name to: \(displayName)")
                        } else {
                            logger.error("❌ currentUser is nil, cannot update displayName")
                        }
                    }
                } else {
                    logger.warning("⚠️ displayName field is missing or empty in Firestore document")
                }
            } else {
                logger.warning("⚠️ Firestore document does not exist for userId: \(userId)")
            }
        } catch {
            logger.error("❌ Failed to fetch displayName: \(error)")
        }
    }
}
