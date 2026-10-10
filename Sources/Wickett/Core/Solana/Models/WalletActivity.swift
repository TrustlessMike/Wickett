import Foundation
import SwiftUI

/// User-friendly wallet activity type (NO blockchain jargon)
enum WalletActivityType: String, Codable {
    case sent = "sent"
    case received = "received"
    case swapped = "swapped"

    var icon: String {
        switch self {
        case .sent: return "arrow.up.circle.fill"
        case .received: return "arrow.down.circle.fill"
        case .swapped: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .sent: return .gray
        case .received: return .green
        case .swapped: return .blue
        }
    }

    var displayName: String {
        switch self {
        case .sent: return "Sent"
        case .received: return "Received"
        case .swapped: return "Swapped"
        }
    }
}

/// Wallet activity status
enum WalletActivityStatus: String, Codable {
    case pending = "pending"
    case completed = "completed"
    case failed = "failed"

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .completed: return .green
        case .failed: return .red
        }
    }
}

/// User-friendly transaction/activity model
/// Hides blockchain complexity from users
struct WalletActivity: Identifiable, Codable {
    let id: String
    let type: WalletActivityType
    let status: WalletActivityStatus

    // Primary amount (always shown)
    let primaryToken: String            // "SOL", "USDC"
    let primaryAmount: Decimal          // 1.5
    let primaryUSDValue: Decimal        // 245.50

    // Secondary amount (for swaps only)
    let secondaryToken: String?         // "USDC" (for swaps)
    let secondaryAmount: Decimal?       // 245.50
    let secondaryUSDValue: Decimal?

    // Counterparty (for sends/receives)
    let counterparty: String?           // "Mike", "Sarah", or wallet address
    let counterpartyAddress: String?    // Full wallet address (hidden by default)

    // Metadata
    let timestamp: Date
    let description: String             // User-friendly description

    // Blockchain details (hidden by default, for power users)
    let signature: String?              // Transaction signature
    let explorerUrl: String?            // Solscan link

    // Fee information
    let feePaidByWickett: Bool          // Always true for our app!

    init(
        id: String = UUID().uuidString,
        type: WalletActivityType,
        status: WalletActivityStatus,
        primaryToken: String,
        primaryAmount: Decimal,
        primaryUSDValue: Decimal,
        secondaryToken: String? = nil,
        secondaryAmount: Decimal? = nil,
        secondaryUSDValue: Decimal? = nil,
        counterparty: String? = nil,
        counterpartyAddress: String? = nil,
        timestamp: Date = Date(),
        description: String,
        signature: String? = nil,
        explorerUrl: String? = nil,
        feePaidByWickett: Bool = true
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.primaryToken = primaryToken
        self.primaryAmount = primaryAmount
        self.primaryUSDValue = primaryUSDValue
        self.secondaryToken = secondaryToken
        self.secondaryAmount = secondaryAmount
        self.secondaryUSDValue = secondaryUSDValue
        self.counterparty = counterparty
        self.counterpartyAddress = counterpartyAddress
        self.timestamp = timestamp
        self.description = description
        self.signature = signature
        self.explorerUrl = explorerUrl
        self.feePaidByWickett = feePaidByWickett
    }

    // MARK: - Display Helpers

    /// Primary amount display (e.g., "1.5 SOL")
    var displayPrimaryAmount: String {
        formatAmount(primaryAmount, token: primaryToken)
    }

    /// Primary USD value display (e.g., "$245.50")
    var displayPrimaryUSD: String {
        formatUSD(primaryUSDValue)
    }

    /// Secondary amount display (e.g., "245.50 USDC")
    var displaySecondaryAmount: String? {
        guard let token = secondaryToken, let amount = secondaryAmount else { return nil }
        return formatAmount(amount, token: token)
    }

    /// Title for activity (e.g., "Sent SOL", "Received USDC", "Swapped SOL → USDC")
    var title: String {
        switch type {
        case .sent:
            if let counterparty = counterparty {
                return "Sent \(primaryToken) to \(counterparty)"
            }
            return "Sent \(primaryToken)"

        case .received:
            if let counterparty = counterparty {
                return "Received \(primaryToken) from \(counterparty)"
            }
            return "Received \(primaryToken)"

        case .swapped:
            if let secondaryToken = secondaryToken {
                return "Swapped \(primaryToken) → \(secondaryToken)"
            }
            return "Swapped \(primaryToken)"
        }
    }

    /// Subtitle for activity (amount + time)
    var subtitle: String {
        let amount = displayPrimaryAmount
        let time = formatTimestamp(timestamp)
        return "\(amount) • \(time)"
    }

    /// Short wallet address display (first 4 + last 4 characters)
    func shortenAddress(_ address: String) -> String {
        guard address.count > 8 else { return address }
        let start = address.prefix(4)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    // MARK: - Private Helpers

    private func formatAmount(_ amount: Decimal, token: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 4
        let amountStr = formatter.string(from: amount as NSDecimalNumber) ?? "0"
        return "\(amountStr) \(token)"
    }

    private func formatUSD(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }

    // MARK: - Firestore Conversion

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "type": type.rawValue,
            "status": status.rawValue,
            "primaryToken": primaryToken,
            "primaryAmount": NSDecimalNumber(decimal: primaryAmount).doubleValue,
            "primaryUSDValue": NSDecimalNumber(decimal: primaryUSDValue).doubleValue,
            "timestamp": timestamp,
            "description": description,
            "feePaidByWickett": feePaidByWickett
        ]

        if let secondaryToken = secondaryToken {
            dict["secondaryToken"] = secondaryToken
        }
        if let secondaryAmount = secondaryAmount {
            dict["secondaryAmount"] = NSDecimalNumber(decimal: secondaryAmount).doubleValue
        }
        if let secondaryUSDValue = secondaryUSDValue {
            dict["secondaryUSDValue"] = NSDecimalNumber(decimal: secondaryUSDValue).doubleValue
        }
        if let counterparty = counterparty {
            dict["counterparty"] = counterparty
        }
        if let counterpartyAddress = counterpartyAddress {
            dict["counterpartyAddress"] = counterpartyAddress
        }
        if let signature = signature {
            dict["signature"] = signature
        }
        if let explorerUrl = explorerUrl {
            dict["explorerUrl"] = explorerUrl
        }

        return dict
    }

    static func from(dictionary: [String: Any]) -> WalletActivity? {
        guard let id = dictionary["id"] as? String,
              let typeString = dictionary["type"] as? String,
              let type = WalletActivityType(rawValue: typeString),
              let statusString = dictionary["status"] as? String,
              let status = WalletActivityStatus(rawValue: statusString),
              let primaryToken = dictionary["primaryToken"] as? String,
              let primaryAmount = dictionary["primaryAmount"] as? Double,
              let primaryUSDValue = dictionary["primaryUSDValue"] as? Double,
              let timestamp = dictionary["timestamp"] as? Date,
              let description = dictionary["description"] as? String else {
            return nil
        }

        let secondaryToken = dictionary["secondaryToken"] as? String
        let secondaryAmount = (dictionary["secondaryAmount"] as? Double).map { Decimal($0) }
        let secondaryUSDValue = (dictionary["secondaryUSDValue"] as? Double).map { Decimal($0) }
        let counterparty = dictionary["counterparty"] as? String
        let counterpartyAddress = dictionary["counterpartyAddress"] as? String
        let signature = dictionary["signature"] as? String
        let explorerUrl = dictionary["explorerUrl"] as? String
        let feePaidByWickett = dictionary["feePaidByWickett"] as? Bool ?? true

        return WalletActivity(
            id: id,
            type: type,
            status: status,
            primaryToken: primaryToken,
            primaryAmount: Decimal(primaryAmount),
            primaryUSDValue: Decimal(primaryUSDValue),
            secondaryToken: secondaryToken,
            secondaryAmount: secondaryAmount,
            secondaryUSDValue: secondaryUSDValue,
            counterparty: counterparty,
            counterpartyAddress: counterpartyAddress,
            timestamp: timestamp,
            description: description,
            signature: signature,
            explorerUrl: explorerUrl,
            feePaidByWickett: feePaidByWickett
        )
    }
}
