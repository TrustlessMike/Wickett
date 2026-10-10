import Foundation

/// Received payment request model
/// Represents a request in the user's inbox (requests they need to pay)
struct ReceivedRequestModel: Identifiable, Codable {
    let id: String // Same as requestId
    let request: PaymentRequest
    let receivedAt: Date?
    let viewedAt: Date?
    var status: RequestStatus
    let rejectionMessage: String?
    let paidAt: Date?
    let rejectedAt: Date?

    var isUnread: Bool {
        viewedAt == nil
    }

    var actionRequired: Bool {
        status == .pending && request.isActive
    }
}
