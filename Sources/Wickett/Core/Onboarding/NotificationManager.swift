import Foundation
import UserNotifications
import UIKit
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "NotificationManager")

/// Manages iOS notification permissions and settings
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Permission Management

    /// Check current notification authorization status
    func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()

        await MainActor.run {
            self.authorizationStatus = settings.authorizationStatus
            self.isAuthorized = settings.authorizationStatus == .authorized
        }

        logger.info("📱 Notification status: \(settings.authorizationStatus.rawValue)")
    }

    /// Request notification permissions from the user
    func requestPermission() async throws {
        logger.info("🔔 Requesting notification permission...")

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

            await MainActor.run {
                self.isAuthorized = granted
                self.authorizationStatus = granted ? .authorized : .denied
            }

            if granted {
                logger.info("✅ Notification permission granted")
            } else {
                logger.info("❌ Notification permission denied")
            }
        } catch {
            logger.error("❌ Failed to request notification permission: \(error)")
            throw NotificationError.permissionDenied
        }
    }

    /// Enable notifications (requests permission if needed)
    func enableNotifications() async throws {
        await checkAuthorizationStatus()

        switch authorizationStatus {
        case .notDetermined:
            try await requestPermission()
        case .denied:
            throw NotificationError.permissionDenied
        case .authorized, .provisional, .ephemeral:
            logger.info("✅ Notifications already authorized")
        @unknown default:
            logger.warning("⚠️ Unknown authorization status")
        }
    }

    /// Disable notifications (updates local state, doesn't revoke system permission)
    func disableNotifications() {
        logger.info("🔕 Notifications disabled by user")
        // Note: We can't programmatically revoke iOS permissions
        // User must do this in Settings if they want to completely disable
    }

    /// Open app settings so user can enable notifications
    func openAppSettings() {
        guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        if UIApplication.shared.canOpenURL(settingsUrl) {
            UIApplication.shared.open(settingsUrl)
            logger.info("📱 Opening app settings")
        }
    }
}

// MARK: - Errors

enum NotificationError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission denied. Please enable notifications in Settings."
        }
    }
}
