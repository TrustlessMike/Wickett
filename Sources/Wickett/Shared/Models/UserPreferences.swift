import Foundation

/// App theme options
enum AppTheme: String, Codable, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var displayName: String {
        return rawValue
    }
}

// MARK: - Fiat Currency

enum FiatCurrency: String, Codable, CaseIterable, Identifiable {
    case usd = "USD"
    case eur = "EUR"
    case gbp = "GBP"
    case jpy = "JPY"
    case cad = "CAD"
    case aud = "AUD"
    case chf = "CHF"
    case cny = "CNY"
    case inr = "INR"
    case mxn = "MXN"

    var id: String { rawValue }

    /// Display name for the currency
    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .gbp: return "British Pound"
        case .jpy: return "Japanese Yen"
        case .cad: return "Canadian Dollar"
        case .aud: return "Australian Dollar"
        case .chf: return "Swiss Franc"
        case .cny: return "Chinese Yuan"
        case .inr: return "Indian Rupee"
        case .mxn: return "Mexican Peso"
        }
    }

    /// Currency symbol
    var symbol: String {
        switch self {
        case .usd: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        case .jpy: return "¥"
        case .cad: return "CA$"
        case .aud: return "A$"
        case .chf: return "CHF"
        case .cny: return "¥"
        case .inr: return "₹"
        case .mxn: return "MX$"
        }
    }

    /// Format amount with currency
    func format(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = rawValue
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(symbol)\(amount)"
    }
}

// MARK: - Legacy Portfolio Allocation

/// Legacy portfolio allocation for UserPreferences (simpler version)
struct LegacyPortfolioAllocation: Codable, Identifiable, Equatable {
    let id: UUID
    var token: String      // Token symbol (e.g., "SOL", "AAPLx")
    var percentage: Double // 0-100

    init(id: UUID = UUID(), token: String, percentage: Double) {
        self.id = id
        self.token = token
        self.percentage = min(max(percentage, 0), 100) // Clamp to 0-100
    }

    /// Format percentage for display
    var formattedPercentage: String {
        String(format: "%.1f%%", percentage)
    }
}

/// User preferences for app settings
struct UserPreferences: Codable {
    // App settings
    var notificationsEnabled: Bool
    var theme: AppTheme

    // Payment preferences
    var localCurrency: FiatCurrency
    var portfolio: [LegacyPortfolioAllocation]
    var preferredPaymentToken: String?

    var createdAt: Date
    var updatedAt: Date

    init(
        notificationsEnabled: Bool = false,
        theme: AppTheme = .system,
        localCurrency: FiatCurrency = .usd,
        portfolio: [LegacyPortfolioAllocation] = [LegacyPortfolioAllocation(token: "SOL", percentage: 100.0)],
        preferredPaymentToken: String? = "SOL",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.notificationsEnabled = notificationsEnabled
        self.theme = theme
        self.localCurrency = localCurrency
        self.portfolio = portfolio
        self.preferredPaymentToken = preferredPaymentToken
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Validate that portfolio percentages sum to 100%
    var isPortfolioValid: Bool {
        let total = portfolio.reduce(0.0) { $0 + $1.percentage }
        return abs(total - 100.0) < 0.01 // Allow small floating point errors
    }

    /// Get portfolio allocation for a specific token
    func allocationFor(token: String) -> Double? {
        portfolio.first(where: { $0.token == token })?.percentage
    }

    /// Convert to Firestore-compatible dictionary
    func toDictionary() -> [String: Any] {
        let portfolioData = portfolio.map { allocation in
            [
                "id": allocation.id.uuidString,
                "token": allocation.token,
                "percentage": allocation.percentage
            ]
        }

        return [
            "notificationsEnabled": notificationsEnabled,
            "theme": theme.rawValue,
            "localCurrency": localCurrency.rawValue,
            "portfolio": portfolioData,
            "preferredPaymentToken": preferredPaymentToken as Any,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
    }

    /// Create from Firestore dictionary
    static func from(dictionary: [String: Any]) -> UserPreferences? {
        guard let notificationsEnabled = dictionary["notificationsEnabled"] as? Bool,
              let themeString = dictionary["theme"] as? String,
              let theme = AppTheme(rawValue: themeString),
              let createdAt = dictionary["createdAt"] as? Date,
              let updatedAt = dictionary["updatedAt"] as? Date else {
            return nil
        }

        // Parse payment preferences (optional for backwards compatibility)
        let localCurrency = (dictionary["localCurrency"] as? String)
            .flatMap { FiatCurrency(rawValue: $0) } ?? .usd

        let portfolio: [LegacyPortfolioAllocation]
        if let portfolioData = dictionary["portfolio"] as? [[String: Any]] {
            portfolio = portfolioData.compactMap { dict in
                guard let idString = dict["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let token = dict["token"] as? String,
                      let percentage = dict["percentage"] as? Double else {
                    return nil
                }
                return LegacyPortfolioAllocation(id: id, token: token, percentage: percentage)
            }
        } else {
            portfolio = [LegacyPortfolioAllocation(token: "SOL", percentage: 100.0)]
        }

        let preferredPaymentToken = dictionary["preferredPaymentToken"] as? String

        return UserPreferences(
            notificationsEnabled: notificationsEnabled,
            theme: theme,
            localCurrency: localCurrency,
            portfolio: portfolio,
            preferredPaymentToken: preferredPaymentToken,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
