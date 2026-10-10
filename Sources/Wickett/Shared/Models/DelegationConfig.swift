import Foundation

/// Portfolio allocation for a single token
struct PortfolioAllocation: Identifiable, Codable, Equatable {
    let id: String
    let token: String       // Token mint address
    let symbol: String      // e.g., "SOL", "USDC", "BONK"
    var percentage: Double  // e.g., 50.0 for 50%

    init(id: String = UUID().uuidString, token: String, symbol: String, percentage: Double) {
        self.id = id
        self.token = token
        self.symbol = symbol
        self.percentage = percentage
    }

    func toDictionary() -> [String: Any] {
        return [
            "token": token,
            "symbol": symbol,
            "percentage": percentage
        ]
    }
}

/// Delegation configuration
struct DelegationConfig: Codable {
    let userId: String
    let status: DelegationStatus
    let portfolio: [PortfolioAllocation]
    let maxSwapAmountUsd: Double
    let dailyLimitUsd: Double
    let expiresAt: Date
    let delegateWallet: String
    let createdAt: Date
    let lastSwapAt: Date?
    let totalSwapsExecuted: Int
    let totalVolumeSwappedUsd: Double

    enum DelegationStatus: String, Codable {
        case active
        case revoked
        case expired
        case pending
    }
}

/// Response from getDelegationStatus Cloud Function
struct DelegationStatusResponse: Codable {
    let hasActiveDelegation: Bool
    let delegation: ActiveDelegation?
    let message: String?

    struct ActiveDelegation: Codable {
        let portfolio: [PortfolioAllocation]
        let maxSwapAmountUsd: Double
        let dailyLimitUsd: Double
        let expiresAt: String
        let delegateWallet: String? // Optional - only for legacy SPL delegations
        let privyPolicyId: String? // Optional - only for V2 Privy delegations
        let createdAt: String
        let lastSwapAt: String?
        let totalSwapsExecuted: Int
        let totalVolumeSwappedUsd: Double
        let todayVolumeUsd: Double
        let remainingDailyLimitUsd: Double
    }
}

/// Request to approve delegation (not used - DelegationManager builds requests directly)
struct ApproveDelegationRequest {
    let portfolio: [[String: Any]]
    let maxSwapAmountUsd: Double
    let dailyLimitUsd: Double
    let expirationDays: Int

    func toDictionary() -> [String: Any] {
        return [
            "portfolio": portfolio,
            "maxSwapAmountUsd": maxSwapAmountUsd,
            "dailyLimitUsd": dailyLimitUsd,
            "expirationDays": expirationDays
        ]
    }
}

/// Auto-swap constraints for UI
struct AutoSwapConstraints {
    let maxSwapAmountPerTx: Double
    let maxDailySwapVolume: Double
    let expiresIn: TimeInterval  // seconds

    var expirationDate: Date {
        return Date().addingTimeInterval(expiresIn)
    }
}

/// Supported tokens for portfolio allocation
enum SupportedToken: String, CaseIterable, Identifiable {
    case sol = "SOL"
    case usdc = "USDC"
    case bonk = "BONK"
    case jup = "JUP"
    case weth = "WETH"
    case wbtc = "WBTC"
    case gold = "GOLD"
    case aapl = "AAPL"
    case tsla = "TSLA"
    case nvda = "NVDA"
    case msft = "MSFT"
    case amzn = "AMZN"

    var id: String { rawValue }

    var mint: String {
        switch self {
        case .sol:
            return "So11111111111111111111111111111111111111112"
        case .usdc:
            return "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
        case .bonk:
            return "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263"
        case .jup:
            return "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN"
        case .weth:
            return "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs"
        case .wbtc:
            return "3NZ9JMVBmGAqocyBIC2c7LQCJScmgsAZ6vQqTDzcqmJh"
        case .gold:
            return "GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A"
        case .aapl:
            return "XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp"
        case .tsla:
            return "XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB"
        case .nvda:
            return "Xsc9qvGRsPnJgT2cT42PYLCnFodDhfkHaSPmx9qEh"
        case .msft:
            return "XspzcW1PkUWo8gpXiPvPqxLB7Lv8PPsmnAUeh3dRMX"
        case .amzn:
            return "Xs3eBt7uRfJX8QUs4suhyU8p2M6DoUDrJyWBa8LLZsg"
        }
    }

    var displayName: String {
        switch self {
        case .sol: return "Solana"
        case .usdc: return "USD Coin"
        case .bonk: return "Bonk"
        case .jup: return "Jupiter"
        case .weth: return "Wrapped Ethereum"
        case .wbtc: return "Wrapped Bitcoin"
        case .gold: return "Pax Gold"
        case .aapl: return "Apple (Tokenized)"
        case .tsla: return "Tesla (Tokenized)"
        case .nvda: return "Nvidia (Tokenized)"
        case .msft: return "Microsoft (Tokenized)"
        case .amzn: return "Amazon (Tokenized)"
        }
    }
}
