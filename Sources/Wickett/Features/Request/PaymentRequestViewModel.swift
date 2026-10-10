import SwiftUI
import FirebaseFirestore
import Combine
import OSLog

@MainActor
class PaymentRequestViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "PaymentRequest")
    private let requestService = RequestService.shared

    // MARK: - Published Properties

    // Create Request State
    @Published var amount: String = ""
    @Published var memo: String = ""
    @Published var selectedRecipient: UserSearchResult?
    @Published var recipientSearchQuery: String = ""
    @Published var searchResults: [UserSearchResult] = []
    @Published var isSearching: Bool = false
    @Published var isCreating: Bool = false
    @Published var createError: String?

    private let preferencesService = UserPreferencesService.shared

    // Created Request State
    @Published var createdRequest: PaymentRequest?
    @Published var qrCodeImage: UIImage?
    @Published var showShareSheet: Bool = false

    // My Requests State
    @Published var myRequests: [PaymentRequest] = []
    @Published var isLoadingMyRequests: Bool = false
    @Published var myRequestsError: String?

    // Received Requests State
    @Published var receivedRequests: [ReceivedRequestModel] = []
    @Published var isLoadingReceivedRequests: Bool = false
    @Published var receivedRequestsError: String?

    // Payment State (for fulfilling requests)
    @Published var isPayingRequest: Bool = false
    @Published var paymentError: String?
    @Published var paymentSuccess: Bool = false
    @Published var paymentSignature: String?

    // MARK: - Create Request

    func createRequest() async {
        guard let amountValue = Decimal(string: amount), amountValue > 0 else {
            createError = "Please enter a valid amount"
            return
        }

        isCreating = true
        createError = nil

        do {
            // Create fiat-based request using user's portfolio
            guard preferencesService.preferences.isPortfolioValid else {
                createError = "Your portfolio allocation must total 100%. Please update in Settings."
                isCreating = false
                return
            }

            // Convert LegacyPortfolioAllocation to PortfolioAllocation
            let portfolio = preferencesService.preferences.portfolio.map { legacy in
                PortfolioAllocation(
                    token: SupportedToken(rawValue: legacy.token)?.mint ?? "",
                    symbol: legacy.token,
                    percentage: legacy.percentage
                )
            }

            let request: PaymentRequest

            // Use combined function if recipient is selected (faster - single network call)
            if let recipient = selectedRecipient {
                request = try await requestService.createAndSendFiatRequest(
                    amount: amountValue,
                    currency: "USD",
                    portfolio: portfolio,
                    isFixedAmount: true,
                    memo: memo,
                    recipientUserId: recipient.userId
                )
                logger.info("✅ Request created and sent to: \(recipient.displayName)")
            } else {
                // No recipient - just create the request
                request = try await requestService.createFiatRequest(
                    amount: amountValue,
                    currency: "USD",
                    portfolio: portfolio,
                    isFixedAmount: true,
                    memo: memo
                )
                logger.info("✅ Request created: \(request.id)")
            }

            // Generate QR code
            if let qrImage = QRCodeGenerator.generateQRCode(from: request.solanaPay) {
                qrCodeImage = qrImage
            }

            createdRequest = request

            // Reset form
            amount = ""
            memo = ""
            selectedRecipient = nil
            recipientSearchQuery = ""
            searchResults = []

        } catch {
            logger.error("❌ Failed to create request: \(error.localizedDescription)")
            createError = error.localizedDescription
        }

        isCreating = false
    }

    func resetCreateForm() {
        amount = ""
        memo = ""
        selectedRecipient = nil
        recipientSearchQuery = ""
        searchResults = []
        createError = nil
        createdRequest = nil
        qrCodeImage = nil
    }

    // MARK: - User Search

    func searchForRecipients() async {
        let query = recipientSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty, query.count >= 2 else {
            searchResults = []
            return
        }

        isSearching = true

        do {
            let results = try await requestService.searchUsers(query: query, limit: 10)
            self.searchResults = results
            logger.info("✅ Found \(results.count) users matching '\(query)'")
        } catch {
            logger.error("❌ Search failed: \(error.localizedDescription)")
            self.searchResults = []
        }

        isSearching = false
    }

    // MARK: - My Requests

    func loadMyRequests(status: String? = nil) async {
        isLoadingMyRequests = true
        myRequestsError = nil

        do {
            myRequests = try await requestService.getMyRequests(limit: 50, status: status)
            logger.info("✅ Loaded \(self.myRequests.count) created requests")
        } catch {
            logger.error("❌ Failed to load my requests: \(error.localizedDescription)")
            myRequestsError = error.localizedDescription
        }

        isLoadingMyRequests = false
    }

    // MARK: - Received Requests

    func loadReceivedRequests(status: String? = nil) async {
        isLoadingReceivedRequests = true
        receivedRequestsError = nil

        do {
            receivedRequests = try await requestService.getReceivedRequests(limit: 50, status: status)
            logger.info("✅ Loaded \(self.receivedRequests.count) received requests")
        } catch {
            logger.error("❌ Failed to load received requests: \(error.localizedDescription)")
            receivedRequestsError = error.localizedDescription
        }

        isLoadingReceivedRequests = false
    }

    // MARK: - Send Request to User

    func sendRequestToUser(requestId: String, recipientUserId: String) async throws {
        try await requestService.sendRequestToUser(
            requestId: requestId,
            recipientUserId: recipientUserId
        )
        logger.info("✅ Request sent to user: \(recipientUserId)")
    }

    // MARK: - Reject Request

    func rejectRequest(requestId: String, message: String?) async throws {
        try await requestService.rejectRequest(requestId: requestId, message: message)
        logger.info("✅ Request rejected: \(requestId)")

        // Reload received requests
        await loadReceivedRequests()
    }

    // MARK: - Pay Request (Fulfill)

    func payRequest(request: PaymentRequest, signedTransaction: String) async {
        isPayingRequest = true
        paymentError = nil
        paymentSuccess = false
        paymentSignature = nil

        do {
            let signature = try await requestService.fulfillRequest(
                requestId: request.id,
                signedTransaction: signedTransaction
            )

            logger.info("✅ Request fulfilled: \(request.id), signature: \(signature)")

            paymentSignature = signature
            paymentSuccess = true

            // Reload received requests to update status
            await loadReceivedRequests()

        } catch {
            logger.error("❌ Failed to fulfill request: \(error.localizedDescription)")
            paymentError = error.localizedDescription
        }

        isPayingRequest = false
    }

    func resetPaymentState() {
        isPayingRequest = false
        paymentError = nil
        paymentSuccess = false
        paymentSignature = nil
    }

    // MARK: - Share Request

    func getShareItems(for request: PaymentRequest) -> [Any] {
        var items: [Any] = []

        // Add the shareable link
        items.append(request.shareableLink)

        // Add QR code image if available
        if let qrImage = qrCodeImage {
            items.append(qrImage)
        }

        // Add text description
        let shareText = """
        \(request.requesterName) is requesting \(request.amount) \(request.tokenSymbol)

        \(request.memo)

        Pay with Wickett: \(request.shareableLink)
        """
        items.append(shareText)

        return items
    }

    // MARK: - User Search

    func searchUsers(query: String) async throws -> [UserSearchResult] {
        return try await requestService.searchUsers(query: query, limit: 10)
    }
}
