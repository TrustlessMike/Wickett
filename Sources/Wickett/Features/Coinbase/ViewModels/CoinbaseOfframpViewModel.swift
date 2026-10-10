import SwiftUI
import Combine
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "CoinbaseOfframpViewModel")

/// State for the offramp flow
enum OfframpState {
    case idle
    case creatingSession
    case presentingCheckout
    case awaitingTransfer
    case sendingCrypto
    case pollingStatus
    case completed
    case failed
}

@MainActor
class CoinbaseOfframpViewModel: ObservableObject {
    // MARK: - Published State
    @Published var fiatAmount: String = ""
    @Published var state: OfframpState = .idle
    @Published var errorMessage: String?
    @Published var currentSession: CreateOfframpSessionResponse?
    @Published var transferStatus: CoinbaseTransferStatus?
    @Published var showCheckout = false
    @Published var showTransferPrompt = false

    // MARK: - Dependencies
    private let coinbaseService = CoinbaseService.shared
    private let walletService = SolanaWalletService.shared
    private let privyService = HybridPrivyService.shared

    // MARK: - Private State
    private var statusPollingTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// Whether the user can start an offramp
    var canStartOfframp: Bool {
        state == .idle && !walletAddress.isEmpty && parsedFiatAmount != nil
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

    /// Current USDC balance
    var usdcBalance: Decimal? {
        guard let balance = walletService.balances.first(where: { $0.token.symbol == "USDC" }) else {
            return nil
        }
        return TokenRegistry.USDC.fromLamports(balance.lamports)
    }

    /// Formatted USDC balance
    var formattedUsdcBalance: String {
        guard let balance = usdcBalance else {
            return "$0.00"
        }
        return String(format: "$%.2f", NSDecimalNumber(decimal: balance).doubleValue)
    }

    /// Whether user has sufficient balance
    var hasSufficientBalance: Bool {
        guard let amount = parsedFiatAmount,
              let balance = usdcBalance else {
            return false
        }
        return balance >= Decimal(amount)
    }

    /// Formatted amount for display
    var formattedAmount: String {
        guard let amount = parsedFiatAmount else {
            return "$0.00"
        }
        return String(format: "$%.2f", amount)
    }

    // MARK: - Actions

    /// Start the offramp flow
    func startOfframp() async {
        guard canStartOfframp else {
            errorMessage = "Unable to start cash out. Please try again."
            return
        }

        guard hasSufficientBalance else {
            errorMessage = "Insufficient USDC balance"
            return
        }

        state = .creatingSession
        errorMessage = nil

        logger.info("Starting offramp flow")

        do {
            // Create offramp session
            let session = try await coinbaseService.createOfframpSession(
                walletAddress: walletAddress,
                fiatAmount: parsedFiatAmount!,
                assetSymbol: "USDC",
                country: "US",
                fiatCurrency: "USD"
            )

            currentSession = session
            state = .presentingCheckout
            showCheckout = true

            logger.info("✅ Offramp session created: \(session.sessionId)")
        } catch {
            logger.error("❌ Failed to create offramp session: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            state = .failed
        }
    }

    /// Called when user dismisses the checkout Safari view
    func handleCheckoutDismissed() {
        showCheckout = false

        guard currentSession != nil else {
            state = .idle
            return
        }

        // Now prompt user to send crypto to deposit address
        logger.info("Checkout dismissed, prompting for crypto transfer")
        state = .awaitingTransfer
        showTransferPrompt = true
    }

    /// User confirmed they want to send crypto
    func confirmTransferIntent() {
        showTransferPrompt = false

        guard let session = currentSession else {
            state = .idle
            return
        }

        // In a real implementation, you would:
        // 1. Use SendViewModel to create a transfer to depositAddress
        // 2. Sign and send via Privy
        // 3. Then start polling

        // For now, we'll transition to polling and let the user handle the send manually
        // TODO: Integrate with SendViewModel for seamless USDC transfer

        logger.info("User will send crypto, starting status polling")
        state = .pollingStatus
        startStatusPolling(sessionId: session.sessionId)
    }

    /// Start polling for transfer status
    private func startStatusPolling(sessionId: String) {
        // Cancel any existing polling task
        statusPollingTask?.cancel()

        statusPollingTask = Task {
            var pollCount = 0
            let maxPolls = 120 // Poll for max 10 minutes (120 * 5s = 10 min)

            while pollCount < maxPolls && !Task.isCancelled {
                do {
                    let status = try await coinbaseService.getTransferStatus(
                        sessionId: sessionId,
                        sessionType: "offramp"
                    )

                    transferStatus = status

                    logger.info("Offramp status: \(status.status)")

                    // Check if completed or failed
                    if status.isCompleted {
                        logger.info("🎉 Offramp completed")
                        state = .completed

                        // Refresh wallet balance
                        if let walletAddr = privyService.walletAddress {
                            await walletService.refreshBalances(walletAddress: walletAddr)
                        }

                        // Stop polling
                        return
                    } else if status.isFailed {
                        logger.error("❌ Offramp failed: \(status.failureReason ?? "unknown")")
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
                errorMessage = "Cash out is taking longer than expected. Your funds will arrive once the transfer is confirmed."
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
        transferStatus = nil
        showCheckout = false
        showTransferPrompt = false
    }

    /// Cancel any ongoing operations
    func cancel() {
        statusPollingTask?.cancel()
        state = .idle
        showCheckout = false
        showTransferPrompt = false
    }

    // MARK: - Cleanup

    deinit {
        statusPollingTask?.cancel()
    }
}
