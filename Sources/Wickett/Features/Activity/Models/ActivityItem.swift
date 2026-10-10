import Foundation

/// Activity type matching backend response
enum ActivityType: String, Codable, CaseIterable {
    case autoConvert = "auto_convert"
    case paymentSent = "payment_sent"
    case paymentReceived = "payment_received"
    case requestSent = "request_sent"
    case requestReceived = "request_received"

    /// Map to TransactionFilter for filtering
    var transactionFilter: TransactionFilter {
        switch self {
        case .autoConvert:
            return .conversions
        case .paymentSent:
            return .payments
        case .paymentReceived:
            return .deposits
        case .requestSent, .requestReceived:
            return .all // Requests shown in all
        }
    }

    /// Map to TransactionType for existing UI
    var transactionType: TransactionType {
        switch self {
        case .autoConvert:
            return .conversion
        case .paymentSent:
            return .payment
        case .paymentReceived:
            return .deposit
        case .requestSent:
            return .withdrawal
        case .requestReceived:
            return .deposit
        }
    }
}

/// Activity status
enum ActivityStatus: String, Codable {
    case completed
    case pending
    case failed
}

/// Activity item from backend
struct ActivityItem: Identifiable, Codable {
    let id: String
    let type: ActivityType
    let title: String
    let subtitle: String
    let amount: Double
    let timestamp: Date
    let status: ActivityStatus
    let icon: String

    /// Convert to Transaction for existing UI
    func toTransaction() -> Transaction {
        Transaction(
            id: id,
            type: type.transactionType,
            amount: amount,
            currency: "USD",
            description: "\(title)\n\(subtitle)",
            timestamp: timestamp
        )
    }
}

/// Response from getUserActivity Cloud Function
struct ActivityResponse: Codable {
    let activities: [ActivityItem]
    let hasMore: Bool
}
