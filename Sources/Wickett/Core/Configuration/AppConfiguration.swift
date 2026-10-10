import Foundation

/// Centralized app configuration
enum AppConfiguration {
    // MARK: - Privy Configuration
    enum Privy {
        static let appId = "YOUR_PRIVY_APP_ID"
        static let clientId = "YOUR_PRIVY_CLIENT_ID"
        static let urlScheme = "wickett"
    }

    // MARK: - Firebase Configuration
    enum Firebase {
        static let projectId = "YOUR_FIREBASE_PROJECT_ID"
        static let functionName = "createFirebaseCustomToken"
        static let region = "us-central1"
    }

    // MARK: - App Configuration
    enum App {
        static var bundleId: String { Bundle.main.bundleIdentifier ?? "org.example.Wickett" }
        static let appName = "Wickett"
    }

    // MARK: - Legal & Support URLs
    enum Legal {
        static let termsOfServiceURL = "https://wickett.app/terms"
        static let privacyPolicyURL = "https://wickett.app/privacy"
        static let supportURL = "https://wickett.app/support"
    }
}
