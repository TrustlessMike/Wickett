import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "ThemeManager")

/// Manages app theme and appearance
@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet {
            saveTheme()
            applyTheme()
        }
    }

    @Published var colorScheme: ColorScheme?

    private let userDefaults = UserDefaults.standard
    private let themeKey = "appTheme"

    private init() {
        // Load saved theme or default to system
        if let savedTheme = userDefaults.string(forKey: themeKey),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .system
        }

        applyTheme()
    }

    // MARK: - Theme Management

    /// Set the app theme
    func setTheme(_ theme: AppTheme) {
        logger.info("🎨 Setting theme to: \(theme.rawValue)")
        currentTheme = theme
    }

    /// Apply the current theme to the app
    private func applyTheme() {
        switch currentTheme {
        case .light:
            colorScheme = .light
            logger.info("☀️ Applied light theme")
        case .dark:
            colorScheme = .dark
            logger.info("🌙 Applied dark theme")
        case .system:
            colorScheme = nil
            logger.info("⚙️ Applied system theme")
        }
    }

    /// Save theme preference to UserDefaults
    private func saveTheme() {
        userDefaults.set(currentTheme.rawValue, forKey: themeKey)
        logger.info("💾 Theme saved: \(self.currentTheme.rawValue)")
    }

    // MARK: - Theme Colors

    /// Get primary color for current theme (Wickett brand blue/cyan)
    var primaryColor: Color {
        switch currentTheme {
        case .light:
            return BrandColors.blue
        case .dark:
            return BrandColors.cyan
        case .system:
            return BrandColors.adaptivePrimary
        }
    }

    /// Get background color for current theme
    var backgroundColor: Color {
        switch currentTheme {
        case .light:
            return Color(UIColor.systemBackground)
        case .dark:
            return Color(UIColor.systemBackground)
        case .system:
            return Color(UIColor.systemBackground)
        }
    }

    /// Get secondary background color for current theme
    var secondaryBackgroundColor: Color {
        switch currentTheme {
        case .light:
            return Color(UIColor.secondarySystemBackground)
        case .dark:
            return Color(UIColor.secondarySystemBackground)
        case .system:
            return Color(UIColor.secondarySystemBackground)
        }
    }
}

// MARK: - Haptic Manager (Shared)

/// Centralized manager for haptic feedback
class HapticManager {
    static let shared = HapticManager()

    private init() {}

    // MARK: - Feedback Generators

    /// Light tap feedback (for toggles, buttons)
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    /// Notification feedback (success, error, warning)
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    /// Selection feedback (picker wheels, sliders)
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Convenience Methods

    /// Success vibration (e.g. completed transaction)
    func success() {
        notification(type: .success)
    }

    /// Error vibration (e.g. form validation failed)
    func error() {
        notification(type: .error)
    }

    /// Warning vibration
    func warning() {
        notification(type: .warning)
    }

    /// Light tap (e.g. tab change)
    func lightTap() {
        impact(style: .light)
    }

    /// Medium tap (e.g. button press)
    func mediumTap() {
        impact(style: .medium)
    }

    /// Heavy tap (e.g. major action)
    func heavyTap() {
        impact(style: .heavy)
    }
}
