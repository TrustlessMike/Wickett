import SwiftUI
import FirebaseCore
import FirebaseAuth

@main
struct WickettApp: App {
    @StateObject private var authCoordinator = AuthCoordinator.shared

    init() {
        // Initialize Firebase
        FirebaseApp.configure()

        // Configure Firebase Auth for persistent sessions
        // This enables automatic token refresh for up to 400 days (matching Privy)
        Auth.auth().useAppLanguage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authCoordinator)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
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
