import Foundation

/// Onramp session status
enum CoinbaseOnrampStatus: String, Codable {
    case created = "created"
    case pending = "pending"
    case completed = "completed"
    case failed = "failed"
    case expired = "expired"
}

/// Coinbase onramp session model
struct CoinbaseOnrampSession: Codable, Identifiable {
    let id: String
    let sessionId: String
    let coinbaseSessionId: String
    let checkoutUrl: String
    let status: CoinbaseOnrampStatus
    let walletAddress: String?
    let assetSymbol: String?
    let fiatAmount: Double?
    let cryptoAmount: Double?
    let transactionHash: String?
    let createdAt: String?
    let updatedAt: String?
    let completedAt: String?
    let failureReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId
        case coinbaseSessionId
        case checkoutUrl
        case status
        case walletAddress
        case assetSymbol
        case fiatAmount
        case cryptoAmount
        case transactionHash
        case createdAt
        case updatedAt
        case completedAt
        case failureReason
    }
}

/// Request to create an onramp session
struct CreateOnrampSessionRequest: Codable {
    let walletAddress: String
    let fiatAmount: Double?
    let assetSymbol: String?
    let country: String?
    let fiatCurrency: String?

    init(walletAddress: String, fiatAmount: Double? = nil, assetSymbol: String = "USDC", country: String = "US", fiatCurrency: String = "USD") {
        self.walletAddress = walletAddress
        self.fiatAmount = fiatAmount
        self.assetSymbol = assetSymbol
        self.country = country
        self.fiatCurrency = fiatCurrency
    }
}

/// Response from creating an onramp session
struct CreateOnrampSessionResponse: Codable {
    let sessionId: String
    let coinbaseSessionId: String
    let checkoutUrl: String
    let status: String
}
