import Foundation

/// Represents a user's balance for a specific token
struct TokenBalance: Identifiable, Codable {
    let id: String
    let token: SolanaToken
    let lamports: UInt64         // Raw token amount in smallest unit
    var usdPrice: Decimal        // Current USD price per token
    var change24h: Decimal?      // 24h price change percentage
    let lastUpdated: Date

    init(
        id: String = UUID().uuidString,
        token: SolanaToken,
        lamports: UInt64,
        usdPrice: Decimal = 0,
        change24h: Decimal? = nil,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.token = token
        self.lamports = lamports
        self.usdPrice = usdPrice
        self.change24h = change24h
        self.lastUpdated = lastUpdated
    }

    // MARK: - Computed Properties

    /// Token amount as Decimal (converted from lamports)
    var amount: Decimal {
        token.fromLamports(lamports)
    }

    /// USD value of this balance
    var usdValue: Decimal {
        amount * usdPrice
    }

    /// Display amount with token symbol (e.g., "1.25 SOL")
    var displayAmount: String {
        token.formatAmount(Decimal(lamports))
    }

    /// Display USD value (e.g., "$245.50")
    var displayUSD: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: usdValue as NSDecimalNumber) ?? "$0.00"
    }

    /// Display 24h change (e.g., "+2.3%" or "-1.5%")
    var display24hChange: String? {
        guard let change = change24h else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"

        return formatter.string(from: (change / 100) as NSDecimalNumber)
    }

    /// Whether the 24h change is positive
    var isPositiveChange: Bool {
        guard let change = change24h else { return false }
        return change > 0
    }

    /// Whether user has a non-zero balance
    var hasBalance: Bool {
        lamports > 0
    }

    // MARK: - Helper Methods

    /// Create a balance with zero amount
    static func zero(for token: SolanaToken) -> TokenBalance {
        TokenBalance(
            token: token,
            lamports: 0,
            usdPrice: 0,
            change24h: nil
        )
    }

    /// Update price information
    func withUpdatedPrice(usdPrice: Decimal, change24h: Decimal?) -> TokenBalance {
        TokenBalance(
            id: id,
            token: token,
            lamports: lamports,
            usdPrice: usdPrice,
            change24h: change24h,
            lastUpdated: Date()
        )
    }

    /// Update balance amount (for optimistic updates)
    func withUpdatedBalance(lamports: UInt64) -> TokenBalance {
        TokenBalance(
            id: id,
            token: token,
            lamports: lamports,
            usdPrice: usdPrice,
            change24h: change24h,
            lastUpdated: Date()
        )
    }

    // MARK: - Firestore Conversion

    /// Convert to Firestore-compatible dictionary
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "symbol": token.symbol,
            "lamports": String(lamports), // Store as string to avoid precision loss
            "usdPrice": NSDecimalNumber(decimal: usdPrice).doubleValue,
            "lastUpdated": lastUpdated
        ]

        if let change = change24h {
            dict["change24h"] = NSDecimalNumber(decimal: change).doubleValue
        }

        return dict
    }

    /// Create from Firestore dictionary
    static func from(dictionary: [String: Any]) -> TokenBalance? {
        guard let id = dictionary["id"] as? String,
              let symbol = dictionary["symbol"] as? String,
              let lamportsString = dictionary["lamports"] as? String,
              let lamports = UInt64(lamportsString),
              let token = TokenRegistry.token(for: symbol),
              let usdPrice = dictionary["usdPrice"] as? Double,
              let lastUpdated = dictionary["lastUpdated"] as? Date else {
            return nil
        }

        let change24h = (dictionary["change24h"] as? Double).map { Decimal($0) }

        return TokenBalance(
            id: id,
            token: token,
            lamports: lamports,
            usdPrice: Decimal(usdPrice),
            change24h: change24h,
            lastUpdated: lastUpdated
        )
    }
}
