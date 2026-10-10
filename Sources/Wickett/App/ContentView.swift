import SwiftUI

struct ContentView: View {
    @StateObject private var authCoordinator = AuthCoordinator.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var walletService = SolanaWalletService.shared

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isInitializing = true

    var body: some View {
        Group {
            if isInitializing {
                LoadingView(message: "Setting up your wallet...")
                    .transition(.opacity)
            } else if authCoordinator.isLoading {
                LoadingView(message: "Connecting to your account...")
                    .transition(.opacity)
            } else if !authCoordinator.isAuthenticated {
                LoginView(
                    onAppleSignIn: signInWithApple,
                    onGoogleSignIn: signInWithGoogle
                )
                .transition(.opacity)
            } else if let user = authCoordinator.currentUser {
                // Check if user needs to complete onboarding
                if !onboardingManager.hasCompletedOnboarding {
                    OnboardingCoordinatorView()
                        .environmentObject(onboardingManager)
                        .environmentObject(themeManager)
                        .environmentObject(notificationManager)
                        .environmentObject(authCoordinator)
                        .transition(.opacity)
                } else {
                    // Show main app with tab navigation
                    MainTabView(
                        user: user,
                        onSignOut: signOut
                    )
                    .environmentObject(onboardingManager)
                    .environmentObject(themeManager)
                    .environmentObject(notificationManager)
                    .environmentObject(walletService)
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isInitializing)
        .animation(.easeInOut(duration: 0.3), value: authCoordinator.isLoading)
        .animation(.easeInOut(duration: 0.3), value: authCoordinator.isAuthenticated)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .preferredColorScheme(themeManager.colorScheme)
        .onAppear {
            checkAuthenticationStatus()
        }
    }

    // MARK: - Authentication Actions

    private func signInWithApple() async {
        do {
            try await authCoordinator.signInWithPrivyOAuth()

            // Fetch user data including displayName from Firestore
            await authCoordinator.checkAuthenticationStatus()

            // Check onboarding status after successful sign-in
            if let userId = authCoordinator.currentUser?.id {
                await onboardingManager.checkOnboardingStatus(userId: userId)
                // Switch portfolio history to this user's data
                PortfolioHistoryManager.shared.switchUser(userId: userId)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Apple Sign in failed: \(error.localizedDescription)"
                self.showError = true
            }
        }
    }

    private func signInWithGoogle() async {
        do {
            try await authCoordinator.signInWithPrivyGoogle()

            // Fetch user data including displayName from Firestore
            await authCoordinator.checkAuthenticationStatus()

            // Check onboarding status after successful sign-in
            if let userId = authCoordinator.currentUser?.id {
                await onboardingManager.checkOnboardingStatus(userId: userId)
                // Switch portfolio history to this user's data
                PortfolioHistoryManager.shared.switchUser(userId: userId)
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Google Sign in failed: \(error.localizedDescription)"
                self.showError = true
            }
        }
    }

    private func checkAuthenticationStatus() {
        Task {
            // Start metadata fetch in background - don't block UI
            Task.detached(priority: .background) {
                await TokenMetadataService.shared.initialize()
                await TokenMetadataService.shared.preloadCommonTokens()
            }

            // Check authentication quickly
            await authCoordinator.checkAuthenticationStatus()

            // If we have a user, show the app IMMEDIATELY
            // Don't wait for heavy wallet initialization
            await MainActor.run {
                isInitializing = false
            }

            // Continue background setup if authenticated
            if authCoordinator.isAuthenticated, let userId = authCoordinator.currentUser?.id {
                await onboardingManager.checkOnboardingStatus(userId: userId)

                // Switch portfolio history to this user's data
                PortfolioHistoryManager.shared.switchUser(userId: userId)

                // Initialize wallet service in background using structured concurrency
                if let walletAddress = authCoordinator.currentUser?.walletAddress {
                    Task {
                        // Initialize price feed FIRST to warm up the cache
                        // This happens in parallel with walletService.initialize()
                        async let priceInit: () = PriceFeedService.shared.refreshPrices()
                        async let walletInit: () = walletService.initialize()

                        // Wait for both to complete
                        _ = await (priceInit, walletInit)

                        // Now fetch balances with prices already loaded
                        await walletService.refreshBalances(walletAddress: walletAddress)
                        // Start auto-refresh after initial load completes
                        walletService.startAutoRefresh(walletAddress: walletAddress)
                    }
                }
            }
        }
    }

    private func signOut() async {
        do {
            try await authCoordinator.signOut()

            // Reset onboarding state and wallet service when signing out
            await MainActor.run {
                onboardingManager.resetOnboarding()
                walletService.stopAutoRefresh()
                walletService.clear()
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Sign out failed: \(error.localizedDescription)"
                self.showError = true
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
