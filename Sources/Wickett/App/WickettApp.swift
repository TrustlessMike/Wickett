import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct WickettApp: App {
    init() {
        // Without owner-supplied Firebase and Privy configuration, skip SDK setup:
        // FirebaseApp.configure() aborts when GoogleService-Info.plist is missing.
        guard AppConfiguration.isBackendConfigured else { return }

        // Initialize Firebase
        FirebaseApp.configure()

        // Configure Firebase Auth for persistent sessions
        // This enables automatic token refresh for up to 400 days (matching Privy)
        Auth.auth().useAppLanguage()
    }

    var body: some Scene {
        WindowGroup {
            if AppConfiguration.isBackendConfigured {
                ConfiguredRootView()
            } else {
                BackendSetupView()
            }
        }
    }
}

/// Root for a configured build. Holds the auth singleton so it (and the Firebase/Privy
/// services behind it) is only created once configuration is known to be present.
private struct ConfiguredRootView: View {
    @StateObject private var authCoordinator = AuthCoordinator.shared

    var body: some View {
        ContentView()
            .environmentObject(authCoordinator)
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }

    private func handleDeepLink(_ url: URL) {
        // Handle Privy deep links for authentication callbacks
        #if DEBUG
        print("Received deep link: \(url)")
        #endif
        // Privy SDK will handle privy:// scheme URLs automatically
    }
}
