import Foundation

/// Coinbase Apple Pay order status
enum CoinbaseApplePayOrderStatus: String, Codable {
    case created = "created"
    case pending = "pending"
    case processing = "processing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"
}

/// Request to create an Apple Pay onramp order
struct CreateApplePayOrderRequest: Codable {
    let walletAddress: String
    let email: String
    let phoneNumber: String
    let phoneNumberVerifiedAt: String?
    let paymentAmount: Double?
    let paymentCurrency: String?
    let purchaseAmount: Double?
    let purchaseCurrency: String?

    init(
        walletAddress: String,
        email: String,
        phoneNumber: String,
        phoneNumberVerifiedAt: String? = nil,
        paymentAmount: Double? = nil,
        paymentCurrency: String = "USD",
        purchaseAmount: Double? = nil,
        purchaseCurrency: String = "USDC"
    ) {
        self.walletAddress = walletAddress
        self.email = email
        self.phoneNumber = phoneNumber
        self.phoneNumberVerifiedAt = phoneNumberVerifiedAt
        self.paymentAmount = paymentAmount
        self.paymentCurrency = paymentCurrency
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrency = purchaseCurrency
    }
}

/// Response from creating an Apple Pay order
struct CreateApplePayOrderResponse: Codable {
    let orderId: String
    let sessionId: String
    let paymentLinkUrl: String
    let paymentTotal: String
    let paymentCurrency: String
    let purchaseAmount: String
    let purchaseCurrency: String
    let status: String

    var paymentTotalDouble: Double? {
        Double(paymentTotal)
    }

    var purchaseAmountDouble: Double? {
        Double(purchaseAmount)
    }
}

/// Fee detail in an Apple Pay order
struct ApplePayOrderFee: Codable {
    let type: String
    let amount: String
    let currency: String

    var amountDouble: Double? {
        Double(amount)
    }
}

/// Full Apple Pay order details
struct CoinbaseApplePayOrder: Codable, Identifiable {
    let id: String
    let orderId: String
    let sessionId: String
    let paymentLinkUrl: String
    let paymentTotal: String
    let paymentSubtotal: String
    let paymentCurrency: String
    let purchaseAmount: String
    let purchaseCurrency: String
    let exchangeRate: String
    let fees: [ApplePayOrderFee]?
    let status: CoinbaseApplePayOrderStatus
    let transactionHash: String?
    let createdAt: String?
    let updatedAt: String?

    var paymentTotalDouble: Double? {
        Double(paymentTotal)
    }

    var purchaseAmountDouble: Double? {
        Double(purchaseAmount)
    }

    var exchangeRateDouble: Double? {
        Double(exchangeRate)
    }

    var totalFees: Double {
        fees?.compactMap { $0.amountDouble }.reduce(0, +) ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orderId
        case sessionId
        case paymentLinkUrl
        case paymentTotal
        case paymentSubtotal
        case paymentCurrency
        case purchaseAmount
        case purchaseCurrency
        case exchangeRate
        case fees
        case status
        case transactionHash
        case createdAt
        case updatedAt
    }
}
