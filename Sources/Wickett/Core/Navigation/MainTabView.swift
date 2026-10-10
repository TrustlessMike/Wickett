import SwiftUI

struct MainTabView: View {
    let user: User
    let onSignOut: () async -> Void

    @State private var selectedTab: Tab = .home
    @State private var showSendView = false
    @State private var showRequestView = false

    // Hiding the native tab bar requires a bit of a hack in pure SwiftUI,
    // or we can just use a ZStack with views. ZStack is cleaner for this custom look.

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: - Content
            Group {
                switch selectedTab {
                case .home:
                    EnhancedHomeView(
                        user: user,
                        onSettings: { selectedTab = .settings },
                        onSignOut: onSignOut,
                        onPayTap: { showSendView = true },
                        onRequestTap: { showRequestView = true }
                    )
                case .activity:
                    ActivityView(user: user)
                case .wallet:
                    WalletView(user: user)
                case .settings:
                    SettingsView(
                        user: user,
                        onDismiss: {},
                        onSignOut: onSignOut
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: - Custom Tab Bar
            CustomTabBar(
                selectedTab: $selectedTab,
                onSendTap: {
                    showSendView = true
                }
            )
        }
        .ignoresSafeArea(.keyboard) // Prevent tab bar from moving up with keyboard
        .sheet(isPresented: $showSendView) {
            SendView(user: user)
        }
        .sheet(isPresented: $showRequestView) {
            CreateRequestView(user: user)
        }
    }
}

// MARK: - Tab Enum

enum Tab: String, CaseIterable {
    case home
    case activity
    case wallet
    case settings
}

#Preview {
    MainTabView(
        user: User(
            id: "test",
            email: "test@example.com",
            name: "Test User",
            walletAddress: "ABC123XYZ789ABC123XYZ789", username: nil
        ),
        onSignOut: {}
    )
    .environmentObject(OnboardingManager.shared)
    .environmentObject(ThemeManager.shared)
    .environmentObject(NotificationManager.shared)
}
