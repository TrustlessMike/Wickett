import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Tab
    let onSendTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left Tabs
                TabBarButton(
                    icon: "house",
                    selectedIcon: "house.fill",
                    title: "Home",
                    tab: .home,
                    selectedTab: $selectedTab
                )

                TabBarButton(
                    icon: "list.bullet.rectangle",
                    selectedIcon: "list.bullet.rectangle.fill",
                    title: "Activity",
                    tab: .activity,
                    selectedTab: $selectedTab
                )

                // Center Action Button (Send)
                Button(action: onSendTap) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.primaryGradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: BrandColors.primary.opacity(0.4), radius: 8, x: 0, y: 4)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 60) // Hit area
                }
                .offset(y: -12) // Slightly raised like Venmo/TikTok center buttons often feel

                // Right Tabs
                TabBarButton(
                    icon: "wallet.pass",
                    selectedIcon: "wallet.pass.fill",
                    title: "Wallet",
                    tab: .wallet,
                    selectedTab: $selectedTab
                )

                TabBarButton(
                    icon: "gearshape",
                    selectedIcon: "gearshape.fill",
                    title: "Settings",
                    tab: .settings,
                    selectedTab: $selectedTab
                )
            }
            .padding(.top, 8)
            .background(
                // Clear background for X/TikTok style transparency
                // Or use a gradient fade if you want "some" readability over busy content
                LinearGradient(
                    colors: [
                        Color(UIColor.systemBackground).opacity(0.0),
                        Color(UIColor.systemBackground).opacity(0.9),
                        Color(UIColor.systemBackground)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        // This ensures the content above flows UNDER the tab bar
        .background(Color.clear)
    }

    private func getSafeAreaBottom() -> CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }
}

struct TabBarButton: View {
    let icon: String
    let selectedIcon: String
    let title: String
    let tab: Tab
    @Binding var selectedTab: Tab

    var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 24))
                    .scaleEffect(isSelected ? 1.1 : 1.0)
                    .foregroundColor(isSelected ? BrandColors.primary : .secondary)

                Text(title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? BrandColors.primary : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.blue // Demo background content
        VStack {
            Spacer()
            CustomTabBar(selectedTab: .constant(.home), onSendTap: {})
        }
    }
}
