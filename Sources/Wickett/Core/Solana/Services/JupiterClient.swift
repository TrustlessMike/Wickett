import Foundation
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "JupiterClient")

/// Client for Jupiter DEX integration via Firebase Cloud Functions
@MainActor
class JupiterClient: ObservableObject {
    static let shared = JupiterClient()

    private let firebaseClient = FirebaseCallableClient.shared

    private init() {}

    // MARK: - Quote Fetching

    /// Get a quote for swapping tokens
    /// - Parameters:
    ///   - inputMint: Input token mint address
    ///   - outputMint: Output token mint address
    ///   - amount: Amount to swap (in token units or fiat)
    ///   - isFiatAmount: If true, amount is in fiat currency
    ///   - fiatCurrency: Fiat currency code (e.g., "USD") if isFiatAmount is true
    /// - Returns: QuoteResult with conversion details
    func getQuote(
        inputMint: String,
        outputMint: String,
        amount: Double,
        isFiatAmount: Bool = false,
        fiatCurrency: String? = nil
    ) async throws -> QuoteResult {
        logger.info("🔍 Fetching Jupiter quote: \(amount) \(isFiatAmount ? fiatCurrency ?? "fiat" : "tokens")")

        var data: [String: Any] = [
            "inputMint": inputMint,
            "outputMint": outputMint,
            "amount": amount,
            "isFiatAmount": isFiatAmount
        ]

        if let currency = fiatCurrency {
            data["fiatCurrency"] = currency
        }

        let result = try await firebaseClient.call("getJupiterQuote", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let quoteData = resultData["data"] as? [String: Any] else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Failed to fetch quote"
            throw JupiterError.quoteFailed(error)
        }

        return try parseQuoteResult(from: quoteData)
    }

    /// Parse quote result from Cloud Function response
    private func parseQuoteResult(from data: [String: Any]) throws -> QuoteResult {
        guard let inputAmount = data["inputAmount"] as? Double,
              let outputAmount = data["outputAmount"] as? Double,
              let priceImpact = data["priceImpact"] as? Double else {
            throw JupiterError.invalidResponse
        }

        let routePlan = data["routePlan"] as? [String] ?? []
        let estimatedFee = data["estimatedFee"] as? Double

        return QuoteResult(
            inputAmount: inputAmount,
            outputAmount: outputAmount,
            priceImpact: priceImpact,
            routePlan: routePlan,
            estimatedFee: estimatedFee
        )
    }

    // MARK: - Swap Execution

    /// Execute a swap via Jupiter
    /// - Parameters:
    ///   - inputMint: Input token mint address
    ///   - outputMint: Output token mint address
    ///   - amount: Amount in smallest units (lamports)
    ///   - slippageBps: Slippage tolerance in basis points (e.g., 50 = 0.5%)
    ///   - userWalletAddress: User's wallet address
    /// - Returns: Partially signed transaction to be completed by user
    func executeSwap(
        inputMint: String,
        outputMint: String,
        amount: Int,
        slippageBps: Int = 50,
        userWalletAddress: String
    ) async throws -> String {
        logger.info("💱 Executing Jupiter swap: \(inputMint) → \(outputMint)")

        let data: [String: Any] = [
            "inputMint": inputMint,
            "outputMint": outputMint,
            "amount": amount,
            "slippageBps": slippageBps,
            "userWalletAddress": userWalletAddress
        ]

        let result = try await firebaseClient.call("sponsorJupiterSwap", data: data)

        guard let resultData = result.data as? [String: Any],
              let success = resultData["success"] as? Bool,
              success,
              let responseData = resultData["data"] as? [String: Any],
              let partiallySignedTx = responseData["partiallySignedTransaction"] as? String else {
            let error = (result.data as? [String: Any])?["error"] as? String ?? "Swap failed"
            throw JupiterError.swapFailed(error)
        }

        logger.info("✅ Swap transaction prepared")

        return partiallySignedTx
    }
}

// MARK: - Models

/// Result of a Jupiter quote request
struct QuoteResult {
    let inputAmount: Double
    let outputAmount: Double
    let priceImpact: Double
    let routePlan: [String]
    let estimatedFee: Double?

    /// Exchange rate (output per input)
    var exchangeRate: Double {
        guard inputAmount > 0 else { return 0 }
        return outputAmount / inputAmount
    }
}

// MARK: - Errors

enum JupiterError: LocalizedError {
    case quoteFailed(String)
    case swapFailed(String)
    case invalidResponse
    case insufficientLiquidity

    var errorDescription: String? {
        switch self {
        case .quoteFailed(let message):
            return "Failed to get quote: \(message)"
        case .swapFailed(let message):
            return "Swap failed: \(message)"
        case .invalidResponse:
            return "Invalid response from Jupiter API"
        case .insufficientLiquidity:
            return "Insufficient liquidity for this swap"
        }
    }
}
