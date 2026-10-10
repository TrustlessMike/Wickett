import SwiftUI
import Combine
import OSLog
import FirebaseAuth
import FirebaseFirestore

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "CoinbaseOnrampViewModel")

/// State for the onramp flow
enum OnrampState {
    case idle
    case creatingSession
    case presentingCheckout
    case pollingStatus
    case completed
    case failed
}

@MainActor
class CoinbaseOnrampViewModel: ObservableObject {
    // MARK: - Published State
    @Published var fiatAmount: String = ""
    @Published var state: OnrampState = .idle
    @Published var errorMessage: String?
    @Published var currentSession: CreateOnrampSessionResponse?
    @Published var currentApplePayOrder: CreateApplePayOrderResponse?
    @Published var transferStatus: CoinbaseTransferStatus?
    @Published var showCheckout = false
    @Published var showApplePaySheet = false
    @Published var selectedPaymentMethod: OnrampPaymentMethod = .applePay

    // MARK: - Dependencies
    private let coinbaseService = CoinbaseService.shared
    private let walletService = SolanaWalletService.shared
    private let privyService = HybridPrivyService.shared
    private let authCoordinator = AuthCoordinator.shared

    // MARK: - Private State
    private var statusPollingTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Whether the user can start an onramp
    var canStartOnramp: Bool {
        state == .idle && !walletAddress.isEmpty
    }

    /// User's wallet address
    var walletAddress: String {
        privyService.walletAddress ?? ""
    }

    /// Parsed fiat amount
    var parsedFiatAmount: Double? {
        guard let amount = Double(fiatAmount), amount > 0 else {
            return nil
        }
        return amount
    }

    /// Formatted amount for display
    var formattedAmount: String {
        guard let amount = parsedFiatAmount else {
            return "$0.00"
        }
        return String(format: "$%.2f", amount)
    }

    // MARK: - Actions

    /// Start the onramp flow
    func startOnramp() async {
        guard canStartOnramp else {
            errorMessage = "Unable to start onramp. Please try again."
            return
        }

        state = .creatingSession
        errorMessage = nil

        logger.info("Starting onramp flow with payment method: \(self.selectedPaymentMethod.rawValue)")

        do {
            switch self.selectedPaymentMethod {
            case .applePay:
                try await startApplePayOnramp()
            case .creditCard:
                try await startHostedCheckoutOnramp()
            }
        } catch {
            logger.error("❌ Failed to create onramp: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            state = .failed
        }
    }

    /// Start Apple Pay onramp (headless/native)
    private func startApplePayOnramp() async throws {
        // Get email - try from currentUser first, then fetch from Firestore
        let email: String
        if let userEmail = authCoordinator.currentUser?.email ?? privyService.currentUser?.email {
            email = userEmail
        } else {
            // Fetch email from Firestore
            if let uid = Auth.auth().currentUser?.uid {
                let db = Firestore.firestore()
                let userDoc = try await db.collection("users").document(uid).getDocument()
                if let userData = userDoc.data(), let firestoreEmail = userData["email"] as? String {
                    email = firestoreEmail
                    logger.info("📧 Fetched email from Firestore: \(firestoreEmail)")
                } else {
                    // Fallback: create sanitized email from UID
                    let sanitizedUid = uid.replacingOccurrences(of: ":", with: "-")
                    email = "\(sanitizedUid)@wickett.app"
                    logger.warning("⚠️ No email in Firestore, using fallback: \(email)")
                }
            } else {
                throw CoinbaseError.unauthenticated
            }
        }

        logger.info("Creating Apple Pay order with email: \(email)")

        // Use a placeholder phone number for now (Coinbase requires it but we don't collect it yet)
        let phoneNumber = "+10000000000"

        let order = try await coinbaseService.createApplePayOrder(
            walletAddress: walletAddress,
            email: email,
            phoneNumber: phoneNumber,
            paymentAmount: parsedFiatAmount,
            purchaseAmount: nil,
            paymentCurrency: "USD",
            purchaseCurrency: "USDC"
        )

        currentApplePayOrder = order
        state = .presentingCheckout
        showApplePaySheet = true

        logger.info("✅ Apple Pay order created: \(order.orderId)")
    }

    /// Start hosted checkout onramp (Credit/Debit card)
    private func startHostedCheckoutOnramp() async throws {
        logger.info("Creating hosted checkout session")

        let session = try await coinbaseService.createOnrampSession(
            walletAddress: walletAddress,
            fiatAmount: parsedFiatAmount,
            assetSymbol: "USDC",
            country: "US",
            fiatCurrency: "USD"
        )

        currentSession = session
        state = .presentingCheckout
        showCheckout = true

        logger.info("✅ Hosted checkout session created: \(session.sessionId)")
    }

    /// Called when user dismisses the checkout Safari view
    func handleCheckoutDismissed() {
        showCheckout = false

        guard let session = currentSession else {
            state = .idle
            return
        }

        // Start polling for status updates
        logger.info("Checkout dismissed, starting status polling")
        state = .pollingStatus
        startStatusPolling(sessionId: session.sessionId)
    }

    /// Called when user dismisses the Apple Pay sheet
    func handleApplePayDismissed() {
        showApplePaySheet = false

        guard let order = currentApplePayOrder else {
            state = .idle
            return
        }

        // Start polling for status updates
        logger.info("Apple Pay dismissed, starting status polling")
        state = .pollingStatus
        startStatusPolling(sessionId: order.sessionId)
    }

    /// Start polling for transfer status
    private func startStatusPolling(sessionId: String) {
        // Cancel any existing polling task
        statusPollingTask?.cancel()

        statusPollingTask = Task {
            var pollCount = 0
            let maxPolls = 60 // Poll for max 5 minutes (60 * 5s = 5 min)

            while pollCount < maxPolls && !Task.isCancelled {
                do {
                    let status = try await coinbaseService.getTransferStatus(
                        sessionId: sessionId,
                        sessionType: "onramp"
                    )

                    transferStatus = status

                    logger.info("Onramp status: \(status.status)")

                    // Check if completed or failed
                    if status.isCompleted {
                        logger.info("🎉 Onramp completed")
                        state = .completed

                        // Refresh wallet balance
                        if let walletAddr = privyService.walletAddress {
                            await walletService.refreshBalances(walletAddress: walletAddr)
                        }

                        // Stop polling
                        return
                    } else if status.isFailed {
                        logger.error("❌ Onramp failed: \(status.failureReason ?? "unknown")")
                        errorMessage = status.failureReason ?? "Transfer failed"
                        state = .failed
                        return
                    }

                    // Wait 5 seconds before next poll
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    pollCount += 1
                } catch {
                    logger.error("Status polling error: \(error.localizedDescription)")

                    // On error, wait and retry (don't fail immediately)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    pollCount += 1
                }
            }

            // If we exit the loop without completion, show message
            if pollCount >= maxPolls {
                logger.info("Status polling timed out")
                errorMessage = "Transfer is taking longer than expected. Check your wallet in a few minutes."
                state = .idle
            }
        }
    }

    /// Reset to initial state
    func reset() {
        statusPollingTask?.cancel()
        state = .idle
        errorMessage = nil
        fiatAmount = ""
        currentSession = nil
        currentApplePayOrder = nil
        transferStatus = nil
        showCheckout = false
        showApplePaySheet = false
    }

    /// Cancel any ongoing operations
    func cancel() {
        statusPollingTask?.cancel()
        state = .idle
        showCheckout = false
        showApplePaySheet = false
    }

    // MARK: - Cleanup

    deinit {
        statusPollingTask?.cancel()
    }
}
