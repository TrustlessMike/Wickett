import Foundation
import SwiftUI

/// Represents a Solana token (SOL or SPL token)
struct SolanaToken: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let symbol: String           // "SOL", "USDC", "BONK"
    let name: String            // "Solana", "USD Coin", "Bonk"
    let mint: String?           // Token mint address (nil for native SOL)
    let decimals: Int           // Number of decimal places
    let icon: String            // SF Symbol name
    let coingeckoId: String?    // For price fetching

    /// Color gradient for UI display
    var gradientColors: [Color] {
        switch symbol {
        case "SOL":
            return [Color(red: 0.56, green: 0.13, blue: 0.87), Color(red: 0.20, green: 0.85, blue: 0.84)]
        case "USDC":
            return [Color(red: 0.16, green: 0.45, blue: 0.98), Color(red: 0.20, green: 0.56, blue: 0.99)]
        case "USDT":
            return [Color(red: 0.19, green: 0.65, blue: 0.58), Color(red: 0.14, green: 0.73, blue: 0.66)]
        case "BONK":
            return [Color(red: 0.98, green: 0.49, blue: 0.29), Color(red: 0.98, green: 0.64, blue: 0.18)]
        case "wBTC":
            return [Color(red: 0.95, green: 0.61, blue: 0.07), Color(red: 0.98, green: 0.72, blue: 0.25)]
        case "wETH":
            return [Color(red: 0.39, green: 0.40, blue: 0.66), Color(red: 0.48, green: 0.51, blue: 0.76)]
        case "JUP":
            return [Color(red: 0.18, green: 0.76, blue: 0.65), Color(red: 0.20, green: 0.85, blue: 0.75)]
        case "RAY":
            return [Color(red: 0.33, green: 0.19, blue: 0.64), Color(red: 0.51, green: 0.35, blue: 0.78)]
        default:
            return [Color.blue, Color.purple]
        }
    }

    /// Primary brand color
    var brandColor: Color {
        gradientColors.first ?? .blue
    }

    /// Format amount with proper decimals
    func formatAmount(_ lamports: Decimal) -> String {
        let amount = lamports / Decimal(pow(10.0, Double(decimals)))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal

        // Handle different token decimal precisions
        switch decimals {
        case 9:  // SOL, GOLD
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 4
        case 8:  // xStock tokens (AAPLx, TSLAx, etc.)
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 6
        case 6:  // USDC, USDT, JUP
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        case 5:  // BONK
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 0
        default:
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 4
        }

        if let formatted = formatter.string(from: amount as NSDecimalNumber) {
            return "\(formatted) \(symbol)"
        }
        return "0 \(symbol)"
    }

    /// Convert display amount to lamports
    func toLamports(_ amount: Decimal) -> UInt64 {
        let lamports = amount * Decimal(pow(10.0, Double(decimals)))
        return UInt64(truncating: lamports as NSDecimalNumber)
    }

    /// Convert lamports to decimal amount
    func fromLamports(_ lamports: UInt64) -> Decimal {
        return Decimal(lamports) / Decimal(pow(10.0, Double(decimals)))
    }
}

// MARK: - Token Registry

/// Registry of supported Solana tokens
struct TokenRegistry {
    /// Native SOL token
    static let SOL = SolanaToken(
        id: "solana",
        symbol: "SOL",
        name: "Solana",
        mint: nil,
        decimals: 9,
        icon: "bolt.circle.fill",
        coingeckoId: "solana"
    )

    /// USDC stablecoin
    static let USDC = SolanaToken(
        id: "usd-coin",
        symbol: "USDC",
        name: "USD Coin",
        mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
        decimals: 6,
        icon: "dollarsign.circle.fill",
        coingeckoId: "usd-coin"
    )

    /// USDT stablecoin
    static let USDT = SolanaToken(
        id: "tether",
        symbol: "USDT",
        name: "Tether USD",
        mint: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
        decimals: 6,
        icon: "dollarsign.circle.fill",
        coingeckoId: "tether"
    )

    /// BONK memecoin
    static let BONK = SolanaToken(
        id: "bonk",
        symbol: "BONK",
        name: "Bonk",
        mint: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
        decimals: 5,
        icon: "pawprint.circle.fill",
        coingeckoId: "bonk"
    )

    /// Wrapped Bitcoin
    static let wBTC = SolanaToken(
        id: "wrapped-bitcoin",
        symbol: "wBTC",
        name: "Wrapped Bitcoin",
        mint: "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh",
        decimals: 8,
        icon: "bitcoinsign.circle.fill",
        coingeckoId: "wrapped-bitcoin"
    )

    /// Wrapped Ethereum
    static let wETH = SolanaToken(
        id: "weth",
        symbol: "wETH",
        name: "Wrapped Ethereum",
        mint: "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs",
        decimals: 8,
        icon: "e.circle.fill",
        coingeckoId: "weth"
    )

    /// Jupiter token
    static let JUP = SolanaToken(
        id: "jupiter-exchange-solana",
        symbol: "JUP",
        name: "Jupiter",
        mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
        decimals: 6,
        icon: "globe",
        coingeckoId: "jupiter-exchange-solana"
    )

    /// Raydium token
    static let RAY = SolanaToken(
        id: "raydium",
        symbol: "RAY",
        name: "Raydium",
        mint: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
        decimals: 6,
        icon: "chart.line.uptrend.xyaxis",
        coingeckoId: "raydium"
    )

    /// GOLD token (Titan's gold-backed token)
    static let GOLD = SolanaToken(
        id: "gold",
        symbol: "GOLD",
        name: "Gold",
        mint: "GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A",
        decimals: 6,  // On-chain verified: 6 decimals
        icon: "crown.fill",
        coingeckoId: nil
    )

    // MARK: - xStocks (Tokenized Stocks)

    /// Apple xStock
    static let AAPLx = SolanaToken(
        id: "apple-xstock",
        symbol: "AAPLx",
        name: "Apple xStock",
        mint: "XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp",
        decimals: 8,
        icon: "applelogo",
        coingeckoId: "apple-xstock"
    )

    /// Tesla xStock
    static let TSLAx = SolanaToken(
        id: "tesla-xstock",
        symbol: "TSLAx",
        name: "Tesla xStock",
        mint: "XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB",
        decimals: 8,
        icon: "bolt.car.fill",
        coingeckoId: "tesla-xstock"
    )

    /// NVIDIA xStock
    static let NVDAx = SolanaToken(
        id: "nvidia-xstock",
        symbol: "NVDAx",
        name: "NVIDIA xStock",
        mint: "Xsc9qvGRsPnJgT2cT42PYLCnFodDhfkHaSPmx9qEh",
        decimals: 8,
        icon: "cpu.fill",
        coingeckoId: "nvidia-xstock"
    )

    /// Microsoft xStock
    static let MSFTx = SolanaToken(
        id: "microsoft-xstock",
        symbol: "MSFTx",
        name: "Microsoft xStock",
        mint: "XspzcW1PkUWo8gpXiPvPqxLB7Lv8PPsmnAUeh3dRMX",
        decimals: 8,
        icon: "square.grid.2x2.fill",
        coingeckoId: "microsoft-xstock"
    )

    /// Amazon xStock
    static let AMZNx = SolanaToken(
        id: "amazon-xstock",
        symbol: "AMZNx",
        name: "Amazon xStock",
        mint: "Xs3eBt7uRfJX8QUs4suhyU8p2M6DoUDrJyWBa8LLZsg",
        decimals: 8,
        icon: "shippingbox.fill",
        coingeckoId: "amazon-xstock"
    )

    // MARK: - Token Groups

    /// Main tokens - Core cryptocurrencies and stablecoins
    static let mainTokens: [SolanaToken] = [SOL, USDC, USDT, wBTC, wETH, GOLD]

    /// DeFi tokens - Solana ecosystem DEX and protocol tokens
    static let defiTokens: [SolanaToken] = [JUP, RAY, BONK]

    /// xStock tokens - Tokenized stocks (top 5 most recognizable)
    static let xStockTokens: [SolanaToken] = [AAPLx, TSLAx, NVDAx, MSFTx, AMZNx]

    /// All supported tokens (ordered: main tokens first, then DeFi, then xStocks)
    static let allTokens: [SolanaToken] = mainTokens + defiTokens + xStockTokens

    /// Get token by symbol
    static func token(for symbol: String) -> SolanaToken? {
        return allTokens.first { $0.symbol == symbol }
    }

    /// Get token by mint address
    static func token(forMint mint: String) -> SolanaToken? {
        return allTokens.first { $0.mint == mint }
    }
}
