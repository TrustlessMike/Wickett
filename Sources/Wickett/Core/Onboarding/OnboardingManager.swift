import Foundation
import FirebaseFirestore
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "OnboardingManager")

/// Manages onboarding state and persists to Firestore
@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var onboardingState: OnboardingState
    @Published var hasCompletedOnboarding: Bool

    private let db = Firestore.firestore()
    private let userDefaults = UserDefaults.standard
    private let onboardingKey = "hasCompletedOnboarding"

    private init() {
        // Check UserDefaults for fast local check
        self.hasCompletedOnboarding = userDefaults.bool(forKey: onboardingKey)
        self.onboardingState = OnboardingState()
    }

    // MARK: - Onboarding Completion

    /// Check if user has completed onboarding
    func checkOnboardingStatus(userId: String) async {
        // Always check Firestore for authoritative status (don't trust cache alone)
        do {
            let document = try await db.collection("users").document(userId).getDocument()

            if document.exists,
               let data = document.data(),
               let completed = data["onboardingCompleted"] as? Bool {
                // User exists in Firestore with onboarding status
                await MainActor.run {
                    self.hasCompletedOnboarding = completed
                }

                if completed {
                    userDefaults.set(true, forKey: onboardingKey)
                    logger.info("✅ Onboarding completed (from Firestore)")
                } else {
                    userDefaults.set(false, forKey: onboardingKey)
                    logger.info("⚠️ Onboarding not completed (from Firestore)")
                }
            } else {
                // New user or document doesn't exist - reset cache and show onboarding
                await MainActor.run {
                    self.hasCompletedOnboarding = false
                }
                userDefaults.set(false, forKey: onboardingKey)
                logger.info("🆕 New user - onboarding required")
            }
        } catch {
            logger.error("❌ Failed to check onboarding status: \(error)")
            // On error, default to not completed (safer to show onboarding)
            await MainActor.run {
                self.hasCompletedOnboarding = false
            }
        }
    }

    /// Mark onboarding as complete and save to Firestore
    func completeOnboarding(userId: String) async throws {
        // Guard: Don't re-complete if already done
        guard !hasCompletedOnboarding else {
            logger.info("⏭️ Onboarding already completed, skipping")
            return
        }

        // Log the complete state before validation
        logger.info("🔍 Pre-validation state check:")
        logger.info("   - displayName: '\(self.onboardingState.displayName)'")
        logger.info("   - displayName.isEmpty: \(self.onboardingState.displayName.isEmpty)")
        logger.info("   - hasAcceptedTerms: \(self.onboardingState.hasAcceptedTerms)")
        logger.info("   - isComplete: \(self.onboardingState.isComplete)")

        guard self.onboardingState.isComplete else {
            logger.error("❌ Onboarding incomplete: displayName='\(self.onboardingState.displayName)', termsAccepted=\(self.onboardingState.hasAcceptedTerms)")
            throw OnboardingError.incompleteData
        }

        logger.info("💾 Saving onboarding data to Firestore...")
        logger.info("📝 DisplayName to save: '\(self.onboardingState.displayName)'")
        logger.info("📝 Username to save: '\(self.onboardingState.username ?? "nil")'")
        logger.info("📝 UserID: \(userId)")

        var userData: [String: Any] = [
            "displayName": self.onboardingState.displayName,
            "preferences": self.onboardingState.preferences.toDictionary(),
            "onboardingCompleted": true,
            "onboardingCompletedAt": Date()
        ]

        // Add username if provided
        if let username = self.onboardingState.username {
            userData["username"] = username
        }

        logger.info("📦 Data to save: \(userData)")

        try await db.collection("users").document(userId).setData(userData, merge: true)

        await MainActor.run {
            self.hasCompletedOnboarding = true
        }

        userDefaults.set(true, forKey: onboardingKey)
        logger.info("✅ Onboarding completed and saved successfully")
    }

    // MARK: - State Management

    /// Move to next onboarding step
    func nextStep() {
        if let next = onboardingState.currentStep.next {
            onboardingState.currentStep = next
            logger.info("➡️ Moving to step: \(next.title)")
        }
    }

    /// Move to previous onboarding step
    func previousStep() {
        if let previous = onboardingState.currentStep.previous {
            onboardingState.currentStep = previous
            logger.info("⬅️ Moving to step: \(previous.title)")
        }
    }

    /// Update display name
    func updateDisplayName(_ name: String) {
        onboardingState.displayName = name
        logger.info("👤 Display name updated to: '\(name)'")
        logger.info("📊 Current onboardingState.displayName: '\(self.onboardingState.displayName)'")
    }

    /// Update username
    func updateUsername(_ username: String?) {
        onboardingState.username = username
        if let username = username {
            logger.info("@ Username updated to: '\(username)'")
        } else {
            logger.info("@ Username cleared (skipped)")
        }
    }

    /// Update preferences
    func updatePreferences(_ preferences: UserPreferences) {
        onboardingState.preferences = preferences
        logger.info("⚙️ Preferences updated")
    }

    /// Mark terms as accepted
    func acceptTerms() {
        onboardingState.hasAcceptedTerms = true
        logger.info("📄 Terms accepted")
    }

    /// Mark walkthrough as completed
    func completeWalkthrough() {
        onboardingState.walkthroughCompleted = true
        logger.info("🎓 Walkthrough completed")
    }

    /// Reset onboarding state (for testing or re-onboarding)
    func resetOnboarding() {
        onboardingState = OnboardingState()
        hasCompletedOnboarding = false
        userDefaults.set(false, forKey: onboardingKey)
        logger.info("🔄 Onboarding reset")
    }
}

// MARK: - Errors

enum OnboardingError: LocalizedError {
    case incompleteData
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .incompleteData:
            return "Please complete all required fields"
        case .saveFailed(let message):
            return "Failed to save onboarding data: \(message)"
        }
    }
}
