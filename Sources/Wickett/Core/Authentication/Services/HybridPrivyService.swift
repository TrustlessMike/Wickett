import Foundation
import PrivySDK
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "HybridPrivyService")

/// Service that bridges Privy authentication with Firebase
/// Implements the pattern: Privy Auth → Firebase Custom Token → Firebase Session
@MainActor
class HybridPrivyService: ObservableObject {
    static let shared = HybridPrivyService()

    private var privyClient: (any Privy)?
    private let firebaseCallable = FirebaseCallableClient.shared

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var walletAddress: String?

    private var authenticatedEmail: String?

    /// Public accessor for Privy client (used by DelegationManager for session approvals)
    var client: (any Privy)? {
        return privyClient
    }

    private init() {
        initializePrivySDK()
    }

    // MARK: - Initialization

    private func initializePrivySDK() {
        #if DEBUG
        let loggingConfig = PrivyLoggingConfig(
            logLevel: .verbose,
            logMessage: { level, message in
                print("🔵 PRIVY [\(level)]: \(message)")
            }
        )
        #else
        let loggingConfig = PrivyLoggingConfig(logLevel: .error)
        #endif

        let config = PrivyConfig(
            appId: "cmh5i82000072jl0cixsq20k7",
            appClientId: "client-WY6SJ3DpaUXxFWCWdTG6FANZ2zzDxkaF9kUWjZTqDM5RG",
            loggingConfig: loggingConfig
        )

        privyClient = PrivySdk.initialize(config: config)
        logger.info("✅ Privy SDK initialized")
    }

    // MARK: - Authentication

    /// Authenticate with Privy OAuth (Apple), then bridge to Firebase
    func authenticateWithPrivyOAuth() async throws {
        try await authenticateWithProvider(PrivySDK.OAuthProvider.apple)
    }

    /// Authenticate with Privy OAuth (Google), then bridge to Firebase
    func authenticateWithPrivyGoogle() async throws {
        try await authenticateWithProvider(PrivySDK.OAuthProvider.google)
    }

    /// Generic OAuth authentication with any provider
    private func authenticateWithProvider(_ provider: PrivySDK.OAuthProvider) async throws {
        let providerName = provider == PrivySDK.OAuthProvider.apple ? "Apple" : "Google"
        let emoji = provider == PrivySDK.OAuthProvider.apple ? "🍎" : "🔵"

        logger.info("\(emoji) Starting Privy \(providerName) Sign-In...")

        guard let privy = privyClient else {
            throw HybridPrivyError.authenticationFailed("Privy client not initialized")
        }

        do {
            let privyUser = try await privy.oAuth.login(with: provider, appUrlScheme: "wickett")
            logger.info("✅ Privy authentication successful: \(privyUser.id)")

            // Continue with the rest of authentication
            try await handleSuccessfulAuth(privyUser: privyUser)
        } catch {
            logger.error("❌ Privy OAuth login failed")
            logger.error("📛 Error type: \(type(of: error))")
            logger.error("📛 Error description: \(error.localizedDescription)")
            logger.error("📛 Full error: \(String(describing: error))")

            throw error
        }
    }

    private func handleSuccessfulAuth(privyUser: PrivyUser) async throws {
        logger.info("✅ Privy authentication successful: \(privyUser.id)")

        // Extract email from linked accounts
        for account in privyUser.linkedAccounts {
            if case .email(let emailAccount) = account {
                self.authenticatedEmail = emailAccount.email
                break
            }
            if case .apple(let appleAccount) = account {
                self.authenticatedEmail = appleAccount.email
                break
            }
            if case .google(let googleAccount) = account {
                self.authenticatedEmail = googleAccount.email
                break
            }
        }

        // Bridge to Firebase and get the Firebase UID
        let firebaseUid = try await bridgeToFirebase(privyUser: privyUser)

        // Fetch user data and wallet, passing the Firebase UID for Firestore queries
        await fetchUserData(privyUser: privyUser, firebaseUid: firebaseUid)
    }

    // MARK: - Firebase Bridge

    /// Bridge Privy authentication to Firebase by creating a custom token
    @discardableResult
    private func bridgeToFirebase(privyUser: PrivyUser) async throws -> String {
        logger.info("🔗 Bridging to Firebase...")
        logger.info("🔗 Using Privy user ID: \(privyUser.id)")

        do {
            // Prepare user data for Firebase bridge
            var privyUserData: [String: Any] = [:]

            // Determine authentication method
            var authMethod = "privy_apple"

            // Include email if available (Apple Sign-In)
            if let email = self.authenticatedEmail {
                privyUserData["email"] = email
                logger.info("📧 Including email in Firebase bridge: \(email)")
            }

            // Extract displayName and wallet from linked accounts if available
            var displayName: String? = nil
            var address: String? = nil

            for account in privyUser.linkedAccounts {
                switch account {
                case .email(let emailAcc):
                    displayName = displayName ?? emailAcc.email
                case .embeddedSolanaWallet(let sol):
                    address = sol.address
                default:
                    break
                }
            }

            if let displayName { privyUserData["displayName"] = displayName }
            if let address {
                privyUserData["wallet"] = ["address": address]
                logger.info("💼 Including wallet in Firebase bridge: \(address)")
            }

            // Create Firebase custom token using the Privy user
            let result = try await firebaseCallable.call(
                "createFirebaseCustomToken",
                data: [
                    "authMethod": authMethod,
                    "privyUserId": privyUser.id,
                    "privyUserData": privyUserData,
                    "timestamp": Date().timeIntervalSince1970
                ]
            )

            guard let data = result.data as? [String: Any],
                  let customToken = data["customToken"] as? String else {
                throw HybridPrivyError.authenticationFailed("Failed to create Firebase token")
            }

            // Sign in to Firebase with custom token
            let authResult = try await Auth.auth().signIn(withCustomToken: customToken)

            logger.info("✅ Firebase authentication successful")
            logger.info("👤 Firebase UID: \(authResult.user.uid)")
            logger.info("🔗 Auth method: \(authMethod)")

            // Return the Firebase UID for use in Firestore queries
            return authResult.user.uid

        } catch {
            logger.error("❌ Firebase bridge failed: \(error)")
            throw HybridPrivyError.authenticationFailed("Firebase bridge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - User Data

    private func fetchUserData(privyUser: PrivyUser, firebaseUid: String? = nil) async {
        // Get or create Solana wallet
        var wallet: String? = nil

        // Get Privy user ID (this is what we need for API lookups)
        let privyUserId = privyUser.id
        logger.info("🔑 Privy user ID: \(privyUserId)")

        // First check if user already has a Solana wallet
        for account in privyUser.linkedAccounts {
            if case .embeddedSolanaWallet(let sol) = account {
                wallet = sol.address
                logger.info("💼 Found existing Solana wallet: \(sol.address)")
                break
            }
        }

        // If no wallet exists, create one SERVER-SIDE with authorization key
        // This enables auto-convert functionality since Swift SDK doesn't support addSessionSigner
        if wallet == nil {
            do {
                logger.info("💼 Creating new Solana wallet SERVER-SIDE with auth key...")
                let result = try await firebaseCallable.call(
                    "createServerWallet",
                    data: ["privyUserId": privyUserId]
                )

                if let data = result.data as? [String: Any],
                   let walletAddress = data["walletAddress"] as? String {
                    wallet = walletAddress
                    let hasAuthKey = data["hasAuthKey"] as? Bool ?? false
                    let alreadyExisted = data["alreadyExisted"] as? Bool ?? false
                    logger.info("✅ Server wallet created: \(walletAddress)")
                    logger.info("   Has auth key: \(hasAuthKey)")
                    logger.info("   Already existed: \(alreadyExisted)")
                } else {
                    logger.error("❌ Server wallet creation returned no address")
                }
            } catch {
                logger.error("❌ Failed to create server wallet: \(error)")
                // Fallback to client-side creation (won't have auth key for auto-convert)
                do {
                    logger.info("💼 Falling back to client-side wallet creation...")
                    let solanaWallet = try await privyUser.createSolanaWallet()
                    wallet = solanaWallet.address
                    logger.info("⚠️ Created client-side wallet (no auth key): \(solanaWallet.address)")
                } catch {
                    logger.error("❌ Client-side wallet creation also failed: \(error)")
                }
            }
        }

        // Use Firebase UID for Firestore queries, fall back to Privy ID if not available
        let userId = firebaseUid ?? {
            // If we don't have Firebase UID, construct it the same way the Cloud Function does
            let privyId = privyUser.id
            return privyId.starts(with: "privy_") ? privyId : "privy_\(privyId)"
        }()

        // CRITICAL: Update Firestore with wallet address AND Privy user ID
        // The privyUserId is required for Privy API lookups (auto-convert)
        // This ensures both are persisted in the database for use by Cloud Functions
        if let wallet = wallet {
            do {
                let db = Firestore.firestore()
                var userData: [String: Any] = [
                    "walletAddress": wallet,
                    "privyUserId": privyUserId as NSObject,
                    "updatedAt": Date()
                ]

                try await db.collection("users").document(userId).setData(userData, merge: true)
                logger.info("✅ Updated Firestore with wallet address: \(wallet)")
                logger.info("✅ Stored Privy user ID: \(privyUserId)")
            } catch {
                logger.error("❌ Failed to update wallet address in Firestore: \(error)")
                // Don't throw - this is not a fatal error, continue with auth
            }
        }

        await MainActor.run {
            self.isAuthenticated = true
            self.currentUser = User(
                id: userId,  // Use Firebase UID instead of Privy ID
                email: self.authenticatedEmail,
                name: nil,
                walletAddress: wallet,
                username: nil
            )
            self.walletAddress = wallet
        }

        logger.info("✅ User data fetched successfully")
        if let wallet = wallet {
            logger.info("💼 Wallet address: \(wallet)")
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        logger.info("🚪 Signing out...")

        // Get current user and sign out from Privy
        if let user = await privyClient?.getUser() {
            await user.logout()
        }

        // Sign out from Firebase
        try Auth.auth().signOut()

        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
            self.walletAddress = nil
            self.authenticatedEmail = nil
        }

        logger.info("✅ Signed out successfully")
    }

    // MARK: - Privy Access

    /// Get the current Privy user for signing transactions
    func getPrivyUser() async throws -> PrivyUser? {
        guard let privy = privyClient else {
            logger.error("❌ Privy client not initialized")
            return nil
        }

        do {
            let user = try await privy.getUser()
            return user
        } catch {
            logger.error("❌ Failed to get Privy user: \(error)")
            return nil
        }
    }

    /// Sign a message for sponsored transactions using Privy embedded wallet
    /// This triggers user approval in the Privy UI
    func signMessageForSponsorship(_ message: String) async throws -> (signature: String, walletAddress: String) {
        guard let privy = privyClient else {
            logger.error("❌ Privy client not initialized")
            throw HybridPrivyError.authenticationFailed("Privy not initialized")
        }

        guard case .authenticated(let privyUser) = privy.authState else {
            logger.error("❌ User not authenticated")
            throw HybridPrivyError.authenticationFailed("User not authenticated")
        }

        logger.info("📝 Getting Solana wallet for signing...")

        // Get the embedded Solana wallets
        let solanaWallets = privyUser.embeddedSolanaWallets
        guard let wallet = solanaWallets.first else {
            logger.error("❌ No Solana wallet found")
            throw HybridPrivyError.authenticationFailed("No Solana wallet found")
        }

        logger.info("💼 Found wallet: \(wallet.address)")
        logger.info("✍️ Requesting signature from Privy...")

        // Get the provider and sign the message
        // This will trigger the Privy UI for user approval
        let provider = wallet.provider
        let signature = try await provider.signMessage(message: message)

        logger.info("✅ Message signed successfully")

        return (signature: signature, walletAddress: wallet.address)
    }

    // MARK: - Helpers

    func isUserAuthenticated() async -> Bool {
        // Check both Privy and Firebase authentication status
        let authState = await privyClient?.getAuthState()
        if case .authenticated = authState {
            // Restore user data from Privy if session exists
            if let privyUser = await privyClient?.getUser() {
                // Check Firebase authentication status
                if let currentUser = Auth.auth().currentUser {
                    logger.info("🔄 Firebase session exists - validating...")
                    do {
                        // First try to get token WITHOUT forcing refresh
                        // Firebase SDK will auto-refresh if needed (much faster)
                        let tokenResult = try await currentUser.getIDTokenResult(forcingRefresh: false)
                        logger.info("✅ Firebase session is valid")

                        // Check token expiration - refresh proactively if expiring soon (within 5 minutes)
                        let expirationTime = tokenResult.expirationDate.timeIntervalSinceNow
                        if expirationTime < 300 { // Less than 5 minutes remaining
                            logger.info("⏰ Token expiring soon (\(Int(expirationTime))s), refreshing proactively...")
                            _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                            logger.info("✅ Firebase token proactively refreshed")
                        }

                        // Get Firebase UID for Firestore queries
                        let firebaseUid = currentUser.uid
                        await fetchUserData(privyUser: privyUser, firebaseUid: firebaseUid)
                    } catch {
                        // Token refresh failed, try forcing a refresh
                        logger.info("⚠️ Auto-refresh failed, attempting manual refresh...")
                        do {
                            _ = try await currentUser.getIDTokenResult(forcingRefresh: true)
                            logger.info("✅ Firebase token manually refreshed")

                            // Get Firebase UID for Firestore queries
                            let firebaseUid = currentUser.uid
                            await fetchUserData(privyUser: privyUser, firebaseUid: firebaseUid)
                        } catch {
                            // Both auto and manual refresh failed, re-authenticate
                            logger.info("🔄 Token refresh failed - re-authenticating via Privy...")
                            do {
                                let firebaseUid = try await bridgeToFirebase(privyUser: privyUser)
                                await fetchUserData(privyUser: privyUser, firebaseUid: firebaseUid)
                            } catch {
                                logger.error("❌ Failed to re-authenticate with Firebase: \(error)")
                                return false
                            }
                        }
                    }
                } else {
                    // No Firebase session, need to authenticate
                    logger.info("🔄 No Firebase session - authenticating...")
                    do {
                        let firebaseUid = try await bridgeToFirebase(privyUser: privyUser)
                        await fetchUserData(privyUser: privyUser, firebaseUid: firebaseUid)
                    } catch {
                        logger.error("❌ Failed to authenticate with Firebase: \(error)")
                        return false
                    }
                }
            }
            return Auth.auth().currentUser != nil
        }
        return false
    }
}

// MARK: - Errors

enum HybridPrivyError: LocalizedError {
    case invalidCredential
    case missingToken
    case authenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential"
        case .missingToken:
            return "Missing identity token"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        }
    }
}
