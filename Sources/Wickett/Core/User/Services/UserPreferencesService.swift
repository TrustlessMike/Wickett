import Foundation
import FirebaseFirestore
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "UserPreferencesService")

/// Service for managing user preferences in Firebase
@MainActor
class UserPreferencesService: ObservableObject {
    static let shared = UserPreferencesService()

    @Published var preferences: UserPreferences

    private let db = Firestore.firestore()
    private var currentUserId: String?

    private init() {
        // Initialize with defaults
        self.preferences = UserPreferences()
    }

    // MARK: - Load Preferences

    /// Load user preferences from Firebase
    func loadPreferences(userId: String) async throws {
        self.currentUserId = userId

        logger.info("📥 Loading preferences for user: \(userId)")

        let docRef = db.collection("users").document(userId)
        let document = try await docRef.getDocument()

        if document.exists, let data = document.data() {
            logger.info("✅ Preferences document found")

            if let prefs = UserPreferences.from(dictionary: data) {
                await MainActor.run {
                    self.preferences = prefs
                }
                logger.info("✅ Loaded preferences: currency=\(prefs.localCurrency.rawValue), portfolio=\(prefs.portfolio.count) tokens")
            } else {
                // Data exists but parsing failed, use defaults
                logger.warning("⚠️ Failed to parse preferences, using defaults")
                await savePreferences(preferences)
            }
        } else {
            // No preferences exist, create defaults
            logger.info("📝 No preferences found, creating defaults")
            await savePreferences(preferences)
        }
    }

    // MARK: - Save Preferences

    /// Save user preferences to Firebase
    func savePreferences(_ prefs: UserPreferences) async {
        guard let userId = currentUserId else {
            logger.error("❌ Cannot save preferences: no userId set")
            return
        }

        logger.info("💾 Saving preferences for user: \(userId)")

        var prefsToSave = prefs
        prefsToSave.updatedAt = Date()

        let docRef = db.collection("users").document(userId)

        do {
            try await docRef.setData(prefsToSave.toDictionary(), merge: true)

            await MainActor.run {
                self.preferences = prefsToSave
            }

            // Update shared data for iMessage extension (future use)
            SharedDataManager.shared.updatePreferredToken(prefsToSave.preferredPaymentToken ?? "SOL")

            logger.info("✅ Preferences saved successfully")
        } catch {
            logger.error("❌ Failed to save preferences: \(error.localizedDescription)")
        }
    }

    // MARK: - Update Individual Settings

    /// Update local currency preference
    func updateLocalCurrency(_ currency: FiatCurrency) async {
        logger.info("💱 Updating currency to: \(currency.rawValue)")

        var updated = preferences
        updated.localCurrency = currency

        await savePreferences(updated)
    }

    /// Update portfolio allocation
    func updatePortfolio(_ allocations: [PortfolioAllocation]) async {
        guard validatePortfolio(allocations) else {
            logger.error("❌ Invalid portfolio: percentages must sum to 100%")
            return
        }

        logger.info("📊 Updating portfolio with \(allocations.count) allocations")

        var updated = preferences
        // Convert new PortfolioAllocation to LegacyPortfolioAllocation
        updated.portfolio = allocations.map { allocation in
            LegacyPortfolioAllocation(
                token: allocation.symbol,  // Use symbol instead of mint address
                percentage: allocation.percentage
            )
        }

        await savePreferences(updated)
    }

    /// Update preferred payment token
    func updatePreferredPaymentToken(_ token: String?) async {
        logger.info("💳 Updating preferred payment token to: \(token ?? "nil")")

        var updated = preferences
        updated.preferredPaymentToken = token

        await savePreferences(updated)
    }

    // MARK: - Validation

    /// Validate that portfolio allocations sum to 100%
    private func validatePortfolio(_ allocations: [PortfolioAllocation]) -> Bool {
        let total = allocations.reduce(0.0) { $0 + $1.percentage }
        return abs(total - 100.0) < 0.01 // Allow small floating point errors
    }

    // MARK: - Helpers

    /// Get formatted amount in user's local currency
    func formatAmount(_ amount: Double) -> String {
        preferences.localCurrency.format(amount)
    }

    /// Calculate token amounts based on portfolio allocation
    func calculatePortfolioAmounts(totalFiatAmount: Double) -> [(token: String, fiatAmount: Double)] {
        return preferences.portfolio.map { allocation in
            let amount = totalFiatAmount * (allocation.percentage / 100.0)
            return (token: allocation.token, fiatAmount: amount)
        }
    }
}

// MARK: - SharedDataManager Extension

/// Helper for sharing data with iMessage extension
class SharedDataManager {
    static let shared = SharedDataManager()

    private let suiteName = "group.com.syndicatemike.Wickett"
    private var sharedDefaults: UserDefaults?

    private init() {
        sharedDefaults = UserDefaults(suiteName: suiteName)
    }

    // MARK: - Wallet Data (Read-Only in Extension)

    var walletAddress: String? {
        sharedDefaults?.string(forKey: "wickett.wallet.address")
    }

    var displayName: String? {
        sharedDefaults?.string(forKey: "wickett.user.displayName")
    }

    var preferredToken: String {
        sharedDefaults?.string(forKey: "wickett.user.preferredToken") ?? "SOL"
    }

    // MARK: - Main App Methods (Write)

    func updateWalletAddress(_ address: String) {
        sharedDefaults?.set(address, forKey: "wickett.wallet.address")
    }

    func updateDisplayName(_ name: String) {
        sharedDefaults?.set(name, forKey: "wickett.user.displayName")
    }

    func updatePreferredToken(_ token: String) {
        sharedDefaults?.set(token, forKey: "wickett.user.preferredToken")
    }
}
