import Foundation

/// Offramp session status
enum CoinbaseOfframpStatus: String, Codable {
    case created = "created"
    case awaitingCrypto = "awaiting_crypto"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case expired = "expired"
}

/// Coinbase offramp session model
struct CoinbaseOfframpSession: Codable, Identifiable {
    let id: String
    let sessionId: String
    let coinbaseSessionId: String
    let checkoutUrl: String
    let depositAddress: String
    let status: CoinbaseOfframpStatus
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
        case depositAddress
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

/// Request to create an offramp session
struct CreateOfframpSessionRequest: Codable {
    let walletAddress: String
    let fiatAmount: Double
    let assetSymbol: String?
    let country: String?
    let fiatCurrency: String?

    init(walletAddress: String, fiatAmount: Double, assetSymbol: String = "USDC", country: String = "US", fiatCurrency: String = "USD") {
        self.walletAddress = walletAddress
        self.fiatAmount = fiatAmount
        self.assetSymbol = assetSymbol
        self.country = country
        self.fiatCurrency = fiatCurrency
    }
}

/// Response from creating an offramp session
struct CreateOfframpSessionResponse: Codable {
    let sessionId: String
    let coinbaseSessionId: String
    let checkoutUrl: String
    let depositAddress: String
    let status: String
}
