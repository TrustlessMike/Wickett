import SwiftUI

struct OnboardingCoordinatorView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var authCoordinator: AuthCoordinator

    @State private var isCompleting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Apply theme color scheme
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            // Current step view
            Group {
                switch onboardingManager.onboardingState.currentStep {
                case .welcome:
                    WelcomeView(onContinue: handleWelcomeContinue)

                case .displayName:
                    DisplayNameSetupView(
                        displayName: $onboardingManager.onboardingState.displayName,
                        onContinue: handleDisplayNameContinue,
                        onBack: onboardingManager.previousStep
                    )

                case .username:
                    // TODO: Implement UsernameSetupView
                    Text("Username Setup - Coming Soon")
                        .onAppear {
                            handleUsernameSkip()
                        }

                case .preferences:
                    PreferencesSetupView(
                        preferences: $onboardingManager.onboardingState.preferences,
                        onContinue: handlePreferencesContinue,
                        onBack: onboardingManager.previousStep
                    )

                case .walkthrough:
                    WalkthroughView(
                        onContinue: handleWalkthroughContinue,
                        onBack: onboardingManager.previousStep
                    )

                case .terms:
                    TermsAcceptanceView(
                        hasAccepted: $onboardingManager.onboardingState.hasAcceptedTerms,
                        onContinue: handleTermsContinue,
                        onBack: onboardingManager.previousStep
                    )
                }
            }

            // Loading overlay
            if isCompleting {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Setting up your account...")
                        .foregroundColor(.white)
                        .font(.headline)
                }
                .padding(30)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(16)
            }
        }
        .preferredColorScheme(themeManager.colorScheme)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Step Handlers

    private func handleWelcomeContinue() {
        onboardingManager.nextStep()
    }

    private func handleDisplayNameContinue() {
        guard !onboardingManager.onboardingState.displayName.isEmpty else {
            return
        }
        onboardingManager.updateDisplayName(onboardingManager.onboardingState.displayName)
        onboardingManager.nextStep()
    }

    private func handleUsernameContinue(username: String?) {
        if let username = username {
            // TODO: Implement username service
            onboardingManager.updateUsername(username)
            onboardingManager.nextStep()
        } else {
            // No username provided, skip
            onboardingManager.updateUsername(nil)
            onboardingManager.nextStep()
        }
    }

    private func handleUsernameSkip() {
        onboardingManager.updateUsername(nil)
        onboardingManager.nextStep()
    }

    private func handlePreferencesContinue() {
        // Apply theme immediately
        themeManager.setTheme(onboardingManager.onboardingState.preferences.theme)

        onboardingManager.updatePreferences(onboardingManager.onboardingState.preferences)
        onboardingManager.nextStep()
    }

    private func handleWalkthroughContinue() {
        onboardingManager.completeWalkthrough()
        onboardingManager.nextStep()
    }

    private func handleTermsContinue() {
        guard onboardingManager.onboardingState.hasAcceptedTerms else {
            return
        }

        onboardingManager.acceptTerms()

        Task {
            await completeOnboarding()
        }
    }

    // MARK: - Completion

    private func completeOnboarding() async {
        guard let userId = authCoordinator.currentUser?.id else {
            errorMessage = "User not authenticated"
            showError = true
            return
        }

        isCompleting = true

        do {
            try await onboardingManager.completeOnboarding(userId: userId)

            // Refresh user data to fetch the displayName from Firestore
            await authCoordinator.checkAuthenticationStatus()

            // Successfully completed
            await MainActor.run {
                isCompleting = false
            }
        } catch {
            await MainActor.run {
                isCompleting = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

#Preview {
    OnboardingCoordinatorView()
        .environmentObject(OnboardingManager.shared)
        .environmentObject(ThemeManager.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthCoordinator.shared)
}
