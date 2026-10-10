import Foundation

/// User's account balance information
struct AccountBalance: Codable {
    var totalBalanceUSD: Double
    var lastUpdated: Date

    init(totalBalanceUSD: Double = 0.0, lastUpdated: Date = Date()) {
        self.totalBalanceUSD = totalBalanceUSD
        self.lastUpdated = lastUpdated
    }

    /// Format balance for display
    var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: totalBalanceUSD)) ?? "$0.00"
    }

    /// Convert to Firestore-compatible dictionary
    func toDictionary() -> [String: Any] {
        return [
            "totalBalanceUSD": totalBalanceUSD,
            "lastUpdated": lastUpdated
        ]
    }

    /// Create from Firestore dictionary
    static func from(dictionary: [String: Any]) -> AccountBalance? {
        guard let totalBalanceUSD = dictionary["totalBalanceUSD"] as? Double,
              let lastUpdated = dictionary["lastUpdated"] as? Date else {
            return nil
        }

        return AccountBalance(
            totalBalanceUSD: totalBalanceUSD,
            lastUpdated: lastUpdated
        )
    }
}
