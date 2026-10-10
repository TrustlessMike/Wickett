import Foundation

// MARK: - Jupiter Quote Models

/// Quote response from Jupiter API via Firebase Cloud Function
struct JupiterQuote: Codable {
    let inputMint: String
    let outputMint: String
    let inAmount: String
    let outAmount: String
    let priceImpactPct: String
    let slippageBps: Int

    /// Computed exchange rate (output/input)
    var exchangeRate: Decimal? {
        guard let inAmountDecimal = Decimal(string: inAmount),
              inAmountDecimal > 0,
              let outAmountDecimal = Decimal(string: outAmount) else {
            return nil
        }
        return outAmountDecimal / inAmountDecimal
    }

    /// Price impact as decimal percentage (e.g., 0.01 for 1%)
    var priceImpact: Decimal? {
        Decimal(string: priceImpactPct)
    }

    /// Slippage tolerance as decimal percentage (e.g., 0.005 for 0.5%)
    var slippagePercentage: Decimal {
        Decimal(slippageBps) / 10000
    }

    /// Minimum output amount after slippage
    func minimumOutputAmount(for token: SolanaToken) -> Decimal? {
        guard let outAmountDecimal = Decimal(string: outAmount) else {
            return nil
        }
        let lamports = token.fromLamports(UInt64(truncating: outAmountDecimal as NSNumber))
        let slippageFactor = 1 - slippagePercentage
        return lamports * slippageFactor
    }

    /// Format input amount for display
    func formattedInputAmount(for token: SolanaToken) -> String {
        guard let inAmountDecimal = Decimal(string: inAmount) else {
            return "0"
        }
        let amount = token.fromLamports(UInt64(truncating: inAmountDecimal as NSNumber))
        return String(format: "%.6f", NSDecimalNumber(decimal: amount).doubleValue)
    }

    /// Format output amount for display
    func formattedOutputAmount(for token: SolanaToken) -> String {
        guard let outAmountDecimal = Decimal(string: outAmount) else {
            return "0"
        }
        let amount = token.fromLamports(UInt64(truncating: outAmountDecimal as NSNumber))
        return String(format: "%.6f", NSDecimalNumber(decimal: amount).doubleValue)
    }
}

/// Swap transaction response from sponsorJupiterSwap Cloud Function
struct JupiterSwapResponse: Codable {
    let success: Bool
    let partiallySignedTransaction: String?  // base64 encoded
    let estimatedFee: Int?                  // in lamports
    let quote: JupiterQuote?
    let error: String?
    let code: String?

    var isSuccess: Bool {
        success && partiallySignedTransaction != nil
    }
}

/// Swap request parameters for sponsorJupiterSwap Cloud Function
struct JupiterSwapRequest: Encodable {
    let inputMint: String
    let outputMint: String
    let amount: Int  // in lamports/smallest unit
    let slippageBps: Int
    let userWalletAddress: String?
}
