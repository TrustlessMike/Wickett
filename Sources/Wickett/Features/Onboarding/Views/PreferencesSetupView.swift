import SwiftUI

struct PreferencesSetupView: View {
    @Binding var preferences: UserPreferences
    let onContinue: () -> Void
    let onBack: () -> Void

    @EnvironmentObject var notificationManager: NotificationManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showingNotificationAlert = false

    var body: some View {
        VStack(spacing: 30) {
            // Progress indicator
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Icon
            Image(systemName: "gearshape.fill")
                .font(.system(size: 80))
                .foregroundColor(BrandColors.primary)

            // Title
            Text("Customize Your Experience")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Set your preferences")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Preferences
            VStack(spacing: 20) {
                // Notifications Toggle
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(BrandColors.primary)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text("Notifications")
                                .font(.headline)
                            Text("Get updates about your transactions")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $preferences.notificationsEnabled)
                            .labelsHidden()
                            .onChange(of: preferences.notificationsEnabled) { newValue in
                                handleNotificationToggle(newValue)
                            }
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }

                // Theme Picker
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "paintbrush.fill")
                            .foregroundColor(BrandColors.primary)
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text("Theme")
                                .font(.headline)
                            Text("Choose your preferred appearance")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Picker("Theme", selection: $preferences.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Image(systemName: themeIcon(for: theme))
                                .tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: preferences.theme) { newTheme in
                        themeManager.setTheme(newTheme)
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                HStack {
                    Text("Continue")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(BrandColors.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
        .alert("Enable Notifications", isPresented: $showingNotificationAlert) {
            Button("Settings") {
                notificationManager.openAppSettings()
            }
            Button("Cancel", role: .cancel) {
                preferences.notificationsEnabled = false
            }
        } message: {
            Text("To receive notifications, please enable them in Settings.")
        }
    }

    private func themeIcon(for theme: AppTheme) -> String {
        switch theme {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "gear"
        }
    }

    private func handleNotificationToggle(_ enabled: Bool) {
        if enabled {
            Task {
                do {
                    try await notificationManager.enableNotifications()
                } catch {
                    // Show alert if permission denied
                    if notificationManager.authorizationStatus == .denied {
                        showingNotificationAlert = true
                    }
                }
            }
        }
    }
}

#Preview {
    PreferencesSetupView(
        preferences: .constant(UserPreferences()),
        onContinue: {},
        onBack: {}
    )
    .environmentObject(NotificationManager.shared)
    .environmentObject(ThemeManager.shared)
}
