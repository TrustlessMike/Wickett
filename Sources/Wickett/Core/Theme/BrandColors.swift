import SwiftUI

/// Wickett brand color palette
enum BrandColors {
    // MARK: - Primary Brand Colors

    /// Main Wickett brand blue #3b9ff5 (59, 159, 245)
    /// Use for primary actions, highlights, and brand identity
    static let blue = Color(red: 59/255, green: 159/255, blue: 245/255)

    /// Wickett brand cyan #00d4c8 (0, 212, 200)
    /// Gradient endpoint and accent color
    static let cyan = Color(red: 0/255, green: 212/255, blue: 200/255)

    /// Alias for primary color (uses blue)
    static let primary = blue

    // MARK: - Semantic Colors

    /// Success color (green) - for positive actions and confirmations
    static let success = Color(red: 0.20, green: 0.78, blue: 0.35)

    /// Warning color (amber) - for cautionary messages
    static let warning = Color(red: 1.00, green: 0.76, blue: 0.03)

    /// Error color (red) - for errors and destructive actions
    static let error = Color(red: 0.96, green: 0.26, blue: 0.21)

    // MARK: - Gradient

    /// Primary brand gradient (blue to cyan) for cards and special UI elements
    static let primaryGradient: LinearGradient = LinearGradient(
        colors: [blue, cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Helper Methods

    /// Get the appropriate brand color based on color scheme
    static func adaptive(light: Color, dark: Color) -> Color {
        // SwiftUI will automatically handle this based on environment
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }

    /// Primary brand color that adapts to dark mode
    /// Uses cyan in dark mode for better contrast
    static var adaptivePrimary: Color {
        adaptive(light: blue, dark: cyan)
    }
}
