import Foundation

/// Transaction type enumeration
enum TransactionType: String, Codable {
    case payment = "Payment"
    case deposit = "Deposit"
    case withdrawal = "Withdrawal"
    case conversion = "Conversion"

    var icon: String {
        switch self {
        case .payment: return "arrow.up.circle.fill"
        case .deposit: return "arrow.down.circle.fill"
        case .withdrawal: return "arrow.up.circle"
        case .conversion: return "arrow.triangle.2.circlepath"
        }
    }

    var color: String {
        switch self {
        case .payment: return "red"
        case .deposit: return "green"
        case .withdrawal: return "orange"
        case .conversion: return "blue"
        }
    }
}

/// Transaction model for recent activity
struct Transaction: Identifiable, Codable {
    let id: String
    let type: TransactionType
    let amount: Double
    let currency: String
    let description: String
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        type: TransactionType,
        amount: Double,
        currency: String,
        description: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.currency = currency
        self.description = description
        self.timestamp = timestamp
    }

    /// Format amount for display
    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2

        let prefix = type == .deposit ? "+" : "-"
        let amountString = formatter.string(from: NSNumber(value: abs(amount))) ?? "$0.00"
        return "\(prefix)\(amountString)"
    }

    /// Format timestamp for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// Convert to Firestore-compatible dictionary
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "type": type.rawValue,
            "amount": amount,
            "currency": currency,
            "description": description,
            "timestamp": timestamp
        ]
    }

    /// Create from Firestore dictionary
    static func from(dictionary: [String: Any]) -> Transaction? {
        guard let id = dictionary["id"] as? String,
              let typeString = dictionary["type"] as? String,
              let type = TransactionType(rawValue: typeString),
              let amount = dictionary["amount"] as? Double,
              let currency = dictionary["currency"] as? String,
              let description = dictionary["description"] as? String,
              let timestamp = dictionary["timestamp"] as? Date else {
            return nil
        }

        return Transaction(
            id: id,
            type: type,
            amount: amount,
            currency: currency,
            description: description,
            timestamp: timestamp
        )
    }
}
