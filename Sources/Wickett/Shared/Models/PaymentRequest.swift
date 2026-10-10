import Foundation

/// Payment request model
struct PaymentRequest: Identifiable, Codable {
    let id: String
    let requesterId: String
    let requesterName: String
    let requesterAddress: String
    let amount: Decimal
    let tokenSymbol: String
    let isFixedAmount: Bool
    let memo: String
    let createdAt: Date
    let expiresAt: Date
    var status: RequestStatus
    let paymentCount: Int
    let lastPaidAt: Date?

    // NEW: Fiat currency support
    let currency: String? // "USD", "EUR", etc. (nil for legacy requests)
    let requesterPortfolio: [PortfolioAllocation]? // How requester wants to receive

    // NEW: Payment details (filled when paid)
    var paidBy: String? // Payer wallet address
    var paidAt: Date? // Payment timestamp
    var paymentToken: String? // Token used for payment
    var transactions: [PaymentTransaction]? // All swap transactions

    // Computed properties
    var token: SolanaToken {
        TokenRegistry.token(for: tokenSymbol) ?? TokenRegistry.SOL
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var isActive: Bool {
        status == .pending && !isExpired
    }

    var formattedAmount: String {
        // If currency is set, format as fiat
        if let curr = currency, let fiatCurrency = FiatCurrency(rawValue: curr) {
            return fiatCurrency.format(Double(truncating: amount as NSNumber))
        }

        // Otherwise format as token amount (legacy)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 6

        if let formatted = formatter.string(from: amount as NSDecimalNumber) {
            return "\(formatted) \(tokenSymbol)"
        }
        return "\(amount) \(tokenSymbol)"
    }

    /// Is this a fiat-based request (vs token-based)
    var isFiatRequest: Bool {
        currency != nil
    }

    var formattedAmountUSD: String? {
        // This would need price data to calculate
        // For now, return nil
        return nil
    }

    var expiresIn: String {
        let now = Date()
        let timeInterval = expiresAt.timeIntervalSince(now)

        if timeInterval <= 0 {
            return "Expired"
        }

        let days = Int(timeInterval / 86400)
        let hours = Int((timeInterval.truncatingRemainder(dividingBy: 86400)) / 3600)

        if days > 0 {
            return "\(days)d \(hours)h"
        } else {
            return "\(hours)h"
        }
    }

    var solanaPay: String {
        // Generate Solana Pay URL
        // Format: solana:{recipient}?amount={amount}&spl-token={mint}&memo={memo}&label={label}
        var url = "solana:\(requesterAddress)"
        var params: [String] = []

        params.append("amount=\(amount)")

        if tokenSymbol != "SOL", let mint = token.mint {
            params.append("spl-token=\(mint)")
        }

        if !memo.isEmpty {
            let encodedMemo = memo.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? memo
            params.append("memo=\(encodedMemo)")
        }

        params.append("label=\(requesterName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? requesterName)")

        if !params.isEmpty {
            url += "?" + params.joined(separator: "&")
        }

        return url
    }

    var shareableLink: String {
        // Deep link format: wickett://request?id={requestId}
        return "wickett://request?id=\(id)"
    }

    var shareText: String {
        return "\(requesterName) is requesting \(formattedAmount) for: \(memo)\n\n\(shareableLink)"
    }
}

/// Request status enum
enum RequestStatus: String, Codable {
    case pending
    case paid
    case expired
    case rejected

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .paid: return "Paid"
        case .expired: return "Expired"
        case .rejected: return "Rejected"
        }
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .paid: return "green"
        case .expired: return "gray"
        case .rejected: return "red"
        }
    }
}

/// Individual payment transaction (for multi-token swaps)
struct PaymentTransaction: Codable, Identifiable {
    let id: UUID
    let token: String // Token symbol (e.g., "SOL", "USDC")
    let amount: Double // Token amount received
    let fiatValue: Double // USD value at time of transaction
    let txSignature: String // Solana transaction signature

    init(id: UUID = UUID(), token: String, amount: Double, fiatValue: Double, txSignature: String) {
        self.id = id
        self.token = token
        self.amount = amount
        self.fiatValue = fiatValue
        self.txSignature = txSignature
    }
}
