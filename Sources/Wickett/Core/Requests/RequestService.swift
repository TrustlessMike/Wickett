import Foundation
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "RequestService")

/// Service for managing payment requests
/// Handles all API calls to Firebase Cloud Functions for request operations
@MainActor
class RequestService: ObservableObject {
    static let shared = RequestService()

    private let firebaseClient = FirebaseCallableClient.shared

    private init() {}

    // MARK: - Create Request

    /// Create a new payment request (token-based - legacy)
    func createRequest(
        amount: Decimal,
        tokenSymbol: String,
        isFixedAmount: Bool,
        memo: String
    ) async throws -> PaymentRequest {
        logger.info("📝 Creating payment request: \(amount) \(tokenSymbol)")

        let data: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "tokenSymbol": tokenSymbol,
            "isFixedAmount": isFixedAmount,
            "memo": memo
        ]

        let result = try await firebaseClient.call("createPaymentRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let requestId = responseData["requestId"] as? String,
              let requestData = responseData["request"] as? [String: Any] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to create request"
            throw RequestError.createFailed(error)
        }

        logger.info("✅ Request created: \(requestId)")
        return try parsePaymentRequest(id: requestId, data: requestData)
    }

    /// Create a new fiat-based payment request
    func createFiatRequest(
        amount: Decimal,
        currency: String,
        portfolio: [PortfolioAllocation],
        isFixedAmount: Bool,
        memo: String
    ) async throws -> PaymentRequest {
        logger.info("📝 Creating fiat payment request: \(amount) \(currency)")

        // Convert portfolio to array of dictionaries
        let portfolioData = portfolio.map { allocation -> [String: Any] in
            return [
                "id": allocation.id,
                "token": allocation.token,
                "symbol": allocation.symbol,
                "percentage": allocation.percentage
            ]
        }

        let data: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency,
            "portfolio": portfolioData,
            "isFixedAmount": isFixedAmount,
            "memo": memo
        ]

        let result = try await firebaseClient.call("createFiatPaymentRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let requestId = responseData["requestId"] as? String,
              let requestData = responseData["request"] as? [String: Any] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to create fiat request"
            throw RequestError.createFailed(error)
        }

        logger.info("✅ Fiat request created: \(requestId)")
        return try parsePaymentRequest(id: requestId, data: requestData)
    }

    // MARK: - Get Requests

    /// Get all requests created by current user
    func getMyRequests(limit: Int = 50, status: String? = nil) async throws -> [PaymentRequest] {
        logger.info("📋 Fetching my requests (limit: \(limit))")

        var data: [String: Any] = ["limit": limit]
        if let status = status {
            data["status"] = status
        }

        let result = try await firebaseClient.call("getMyRequests", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let requestsArray = responseData["requests"] as? [[String: Any]] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to fetch requests"
            throw RequestError.fetchFailed(error)
        }

        let requests = try requestsArray.compactMap { requestData -> PaymentRequest? in
            guard let id = requestData["id"] as? String else { return nil }
            return try? parsePaymentRequest(id: id, data: requestData)
        }

        logger.info("✅ Fetched \(requests.count) requests")
        return requests
    }

    /// Get all requests received by current user (requests to pay)
    func getReceivedRequests(limit: Int = 50, status: String? = nil) async throws -> [ReceivedRequestModel] {
        logger.info("📬 Fetching received requests (limit: \(limit))")

        var data: [String: Any] = ["limit": limit]
        if let status = status {
            data["status"] = status
        }

        let result = try await firebaseClient.call("getReceivedRequests", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let requestsArray = responseData["requests"] as? [[String: Any]] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to fetch received requests"
            throw RequestError.fetchFailed(error)
        }

        let requests = try requestsArray.compactMap { data -> ReceivedRequestModel? in
            return try? parseReceivedRequest(data: data)
        }

        logger.info("✅ Fetched \(requests.count) received requests")
        return requests
    }

    /// Get a specific payment request by ID
    func getRequest(requestId: String) async throws -> PaymentRequest {
        logger.info("🔍 Fetching request: \(requestId)")

        let data: [String: Any] = ["requestId": requestId]

        let result = try await firebaseClient.call("getPaymentRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let id = responseData["id"] as? String else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to fetch request"
            throw RequestError.fetchFailed(error)
        }

        logger.info("✅ Request fetched: \(id)")
        return try parsePaymentRequest(id: id, data: responseData)
    }

    // MARK: - Search Users

    /// Search for users by display name or wallet address
    func searchUsers(query: String, limit: Int = 10) async throws -> [UserSearchResult] {
        logger.info("🔍 Searching users: \(query)")

        let data: [String: Any] = [
            "query": query,
            "limit": limit
        ]

        let result = try await firebaseClient.call("searchUsers", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let resultsArray = responseData["results"] as? [[String: Any]] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to search users"
            throw RequestError.searchFailed(error)
        }

        let users = resultsArray.compactMap { userData -> UserSearchResult? in
            guard let userId = userData["userId"] as? String,
                  let displayName = userData["displayName"] as? String,
                  let walletAddress = userData["walletAddress"] as? String else {
                return nil
            }
            let username = userData["username"] as? String
            return UserSearchResult(
                userId: userId,
                displayName: displayName,
                username: username,
                walletAddress: walletAddress
            )
        }

        logger.info("✅ Found \(users.count) users")
        return users
    }

    // MARK: - Send Notification

    /// Send payment request to specific user
    func sendRequestToUser(requestId: String, recipientUserId: String) async throws {
        logger.info("📬 Sending request \(requestId) to user \(recipientUserId)")

        let data: [String: Any] = [
            "requestId": requestId,
            "recipientUserId": recipientUserId
        ]

        let result = try await firebaseClient.call("sendRequestNotification", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to send request"
            throw RequestError.sendFailed(error)
        }

        logger.info("✅ Request sent successfully")
    }

    // MARK: - Combined Create + Send (Faster)

    /// Create AND send a fiat payment request in a single call (~50% faster)
    func createAndSendFiatRequest(
        amount: Decimal,
        currency: String,
        portfolio: [PortfolioAllocation],
        isFixedAmount: Bool,
        memo: String,
        recipientUserId: String
    ) async throws -> PaymentRequest {
        logger.info("📝 Creating and sending fiat request: \(amount) \(currency) to \(recipientUserId)")

        let portfolioData = portfolio.map { allocation -> [String: Any] in
            return [
                "id": allocation.id,
                "token": allocation.token,
                "symbol": allocation.symbol,
                "percentage": allocation.percentage
            ]
        }

        let data: [String: Any] = [
            "amount": NSDecimalNumber(decimal: amount).doubleValue,
            "currency": currency,
            "portfolio": portfolioData,
            "isFixedAmount": isFixedAmount,
            "memo": memo,
            "recipientUserId": recipientUserId
        ]

        let result = try await firebaseClient.call("createAndSendFiatRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let requestId = responseData["requestId"] as? String,
              let requestData = responseData["request"] as? [String: Any] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to create and send request"
            throw RequestError.createFailed(error)
        }

        logger.info("✅ Request created and sent: \(requestId)")
        return try parsePaymentRequest(id: requestId, data: requestData)
    }

    // MARK: - Fulfill Request

    /// Fulfill (pay) a payment request
    func fulfillRequest(requestId: String, signedTransaction: String, amount: Decimal? = nil) async throws -> String {
        logger.info("💰 Fulfilling request: \(requestId)")

        var data: [String: Any] = [
            "requestId": requestId,
            "signedTransaction": signedTransaction
        ]

        if let amount = amount {
            data["amount"] = NSDecimalNumber(decimal: amount).doubleValue
        }

        let result = try await firebaseClient.call("fulfillPaymentRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let signature = responseData["transactionHash"] as? String else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to fulfill request"
            throw RequestError.fulfillFailed(error)
        }

        logger.info("✅ Request fulfilled: \(signature)")
        return signature
    }

    // MARK: - Reject Request

    /// Reject a payment request with optional message
    func rejectRequest(requestId: String, message: String? = nil) async throws {
        logger.info("❌ Rejecting request: \(requestId)")

        var data: [String: Any] = ["requestId": requestId]
        if let message = message, !message.isEmpty {
            data["message"] = message
        }

        let result = try await firebaseClient.call("rejectPaymentRequest", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to reject request"
            throw RequestError.rejectFailed(error)
        }

        logger.info("✅ Request rejected")
    }

    // MARK: - Parsing Helpers

    private func parsePaymentRequest(id: String, data: [String: Any]) throws -> PaymentRequest {
        guard let requesterId = data["requesterId"] as? String,
              let requesterName = data["requesterName"] as? String,
              let requesterAddress = data["requesterAddress"] as? String,
              let amountDouble = data["amount"] as? Double,
              let tokenSymbol = data["tokenSymbol"] as? String,
              let isFixedAmount = data["isFixedAmount"] as? Bool,
              let memo = data["memo"] as? String,
              let createdAtMillis = data["createdAt"] as? Int64,
              let expiresAtMillis = data["expiresAt"] as? Int64,
              let statusString = data["status"] as? String,
              let paymentCount = data["paymentCount"] as? Int else {
            throw RequestError.invalidData
        }

        let amount = Decimal(amountDouble)
        let createdAt = Date(timeIntervalSince1970: TimeInterval(createdAtMillis) / 1000)
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtMillis) / 1000)
        let status = RequestStatus(rawValue: statusString) ?? .pending
        let lastPaidAt: Date? = {
            if let millis = data["lastPaidAt"] as? Int64 {
                return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            }
            return nil
        }()

        // Parse optional new fields (for backwards compatibility)
        let currency = data["currency"] as? String
        let requesterPortfolioData = data["requesterPortfolio"] as? [[String: Any]]
        let requesterPortfolio = requesterPortfolioData?.compactMap { dict -> PortfolioAllocation? in
            guard let id = dict["id"] as? String,
                  let token = dict["token"] as? String,
                  let symbol = dict["symbol"] as? String,
                  let percentage = dict["percentage"] as? Double else {
                return nil
            }
            return PortfolioAllocation(id: id, token: token, symbol: symbol, percentage: percentage)
        }

        return PaymentRequest(
            id: id,
            requesterId: requesterId,
            requesterName: requesterName,
            requesterAddress: requesterAddress,
            amount: amount,
            tokenSymbol: tokenSymbol,
            isFixedAmount: isFixedAmount,
            memo: memo,
            createdAt: createdAt,
            expiresAt: expiresAt,
            status: status,
            paymentCount: paymentCount,
            lastPaidAt: lastPaidAt,
            currency: currency,
            requesterPortfolio: requesterPortfolio
        )
    }

    private func parseReceivedRequest(data: [String: Any]) throws -> ReceivedRequestModel {
        guard let id = data["id"] as? String,
              let requestData = data["request"] as? [String: Any],
              let statusString = data["status"] as? String else {
            throw RequestError.invalidData
        }

        let request = try parsePaymentRequest(id: id, data: requestData)
        let status = RequestStatus(rawValue: statusString) ?? .pending

        let receivedAt: Date? = {
            if let millis = data["receivedAt"] as? Int64 {
                return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            }
            return nil
        }()

        let viewedAt: Date? = {
            if let millis = data["viewedAt"] as? Int64 {
                return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            }
            return nil
        }()

        let paidAt: Date? = {
            if let millis = data["paidAt"] as? Int64 {
                return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            }
            return nil
        }()

        let rejectedAt: Date? = {
            if let millis = data["rejectedAt"] as? Int64 {
                return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            }
            return nil
        }()

        let rejectionMessage = data["rejectionMessage"] as? String

        return ReceivedRequestModel(
            id: id,
            request: request,
            receivedAt: receivedAt,
            viewedAt: viewedAt,
            status: status,
            rejectionMessage: rejectionMessage,
            paidAt: paidAt,
            rejectedAt: rejectedAt
        )
    }
}

// MARK: - Supporting Types

struct UserSearchResult: Identifiable {
    let userId: String
    let displayName: String
    let username: String?
    let walletAddress: String

    var id: String { userId }

    /// Returns @username if available, otherwise displayName
    var primaryIdentifier: String {
        if let username = username {
            return "@\(username)"
        }
        return displayName
    }

    /// Returns display name with username or wallet as secondary info
    var fullDisplayText: String {
        if let username = username {
            return "@\(username) (\(displayName))"
        }
        return "\(displayName) (\(shortWallet))"
    }

    private var shortWallet: String {
        let wallet = walletAddress
        return String(wallet.prefix(6)) + "..." + String(wallet.suffix(4))
    }
}

// MARK: - Errors

enum RequestError: LocalizedError {
    case createFailed(String)
    case fetchFailed(String)
    case searchFailed(String)
    case sendFailed(String)
    case fulfillFailed(String)
    case rejectFailed(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .createFailed(let message): return "Failed to create request: \(message)"
        case .fetchFailed(let message): return "Failed to fetch requests: \(message)"
        case .searchFailed(let message): return "Failed to search users: \(message)"
        case .sendFailed(let message): return "Failed to send request: \(message)"
        case .fulfillFailed(let message): return "Failed to fulfill request: \(message)"
        case .rejectFailed(let message): return "Failed to reject request: \(message)"
        case .invalidData: return "Invalid data received from server"
        }
    }
}
