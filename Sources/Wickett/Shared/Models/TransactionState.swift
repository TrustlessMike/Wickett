import Foundation

/// Transaction lifecycle state for send/swap operations
enum TransactionState {
    case idle
    case building
    case signing
    case broadcasting
    case confirming
    case completed
    case failed

    var displayMessage: String {
        switch self {
        case .idle:
            return ""
        case .building:
            return "Building transaction..."
        case .signing:
            return "Waiting for signature..."
        case .broadcasting:
            return "Broadcasting to network..."
        case .confirming:
            return "Confirming on blockchain..."
        case .completed:
            return "Transaction completed!"
        case .failed:
            return "Transaction failed"
        }
    }
}
