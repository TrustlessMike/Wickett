import Foundation
import FirebaseFunctions

/// Errors that can occur during Coinbase operations
enum CoinbaseError: LocalizedError {
    case unauthenticated
    case invalidWalletAddress
    case invalidAmount
    case sessionCreationFailed(String)
    case statusCheckFailed(String)
    case networkError(Error)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .unauthenticated:
            return "You must be signed in to use this feature"
        case .invalidWalletAddress:
            return "Invalid wallet address"
        case .invalidAmount:
            return "Please enter a valid amount"
        case .sessionCreationFailed(let message):
            return "Failed to create session: \(message)"
        case .statusCheckFailed(let message):
            return "Failed to check status: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unknownError:
            return "An unknown error occurred"
        }
    }
}

/// Service for interacting with Coinbase onramp/offramp functionality
@MainActor
class CoinbaseService {
    static let shared = CoinbaseService()

    private let firebaseClient = FirebaseCallableClient.shared

    private init() {}

    // MARK: - Onramp (Buy Crypto)

    /// Creates a Coinbase Apple Pay onramp order (headless/native)
    /// - Parameters:
    ///   - walletAddress: User's Solana wallet address
    ///   - email: User's email address
    ///   - phoneNumber: User's phone number
    ///   - paymentAmount: Optional preset amount in fiat currency
    ///   - purchaseAmount: Optional preset amount in crypto
    ///   - paymentCurrency: Fiat currency (default: USD)
    ///   - purchaseCurrency: Crypto to purchase (default: USDC)
    /// - Returns: Apple Pay order with native payment link
    func createApplePayOrder(
        walletAddress: String,
        email: String,
        phoneNumber: String,
        paymentAmount: Double? = nil,
        purchaseAmount: Double? = nil,
        paymentCurrency: String = "USD",
        purchaseCurrency: String = "USDC"
    ) async throws -> CreateApplePayOrderResponse {
        let request = CreateApplePayOrderRequest(
            walletAddress: walletAddress,
            email: email,
            phoneNumber: phoneNumber,
            phoneNumberVerifiedAt: ISO8601DateFormatter().string(from: Date()),
            paymentAmount: paymentAmount,
            paymentCurrency: paymentCurrency,
            purchaseAmount: purchaseAmount,
            purchaseCurrency: purchaseCurrency
        )

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)
            guard let requestDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw CoinbaseError.unknownError
            }

            let result = try await firebaseClient.call(
                "createCoinbaseApplePayOrder",
                data: requestDict,
                timeout: 30
            )

            guard let responseData = result.data as? [String: Any] else {
                throw CoinbaseError.sessionCreationFailed("Invalid response format")
            }

            let responseJson = try JSONSerialization.data(withJSONObject: responseData)
            let decoder = JSONDecoder()
            let response = try decoder.decode(CreateApplePayOrderResponse.self, from: responseJson)

            return response
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw CoinbaseError.unauthenticated
                case .invalidArgument:
                    throw CoinbaseError.invalidWalletAddress
                case .unavailable:
                    throw CoinbaseError.sessionCreationFailed("Service temporarily unavailable")
                default:
                    throw CoinbaseError.sessionCreationFailed(error.localizedDescription)
                }
            }
            throw CoinbaseError.networkError(error)
        }
    }

    /// Creates a Coinbase onramp session (hosted checkout)
    /// - Parameters:
    ///   - walletAddress: User's Solana wallet address
    ///   - fiatAmount: Optional preset amount in fiat currency
    ///   - assetSymbol: Asset to purchase (default: USDC)
    ///   - country: User's country code (default: US)
    ///   - fiatCurrency: Fiat currency (default: USD)
    /// - Returns: Onramp session with checkout URL
    func createOnrampSession(
        walletAddress: String,
        fiatAmount: Double? = nil,
        assetSymbol: String = "USDC",
        country: String = "US",
        fiatCurrency: String = "USD"
    ) async throws -> CreateOnrampSessionResponse {
        let request = CreateOnrampSessionRequest(
            walletAddress: walletAddress,
            fiatAmount: fiatAmount,
            assetSymbol: assetSymbol,
            country: country,
            fiatCurrency: fiatCurrency
        )

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)
            guard let requestDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw CoinbaseError.unknownError
            }

            let result = try await firebaseClient.call(
                "createCoinbaseOnrampSession",
                data: requestDict,
                timeout: 30
            )

            guard let responseData = result.data as? [String: Any] else {
                throw CoinbaseError.sessionCreationFailed("Invalid response format")
            }

            let responseJson = try JSONSerialization.data(withJSONObject: responseData)
            let decoder = JSONDecoder()
            let response = try decoder.decode(CreateOnrampSessionResponse.self, from: responseJson)

            return response
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw CoinbaseError.unauthenticated
                case .invalidArgument:
                    throw CoinbaseError.invalidWalletAddress
                case .unavailable:
                    throw CoinbaseError.sessionCreationFailed("Service temporarily unavailable")
                default:
                    throw CoinbaseError.sessionCreationFailed(error.localizedDescription)
                }
            }
            throw CoinbaseError.networkError(error)
        }
    }

    // MARK: - Offramp (Sell Crypto)

    /// Creates a Coinbase offramp session
    /// - Parameters:
    ///   - walletAddress: User's Solana wallet address
    ///   - fiatAmount: Amount to sell in fiat currency
    ///   - assetSymbol: Asset to sell (default: USDC)
    ///   - country: User's country code (default: US)
    ///   - fiatCurrency: Fiat currency (default: USD)
    /// - Returns: Offramp session with checkout URL and deposit address
    func createOfframpSession(
        walletAddress: String,
        fiatAmount: Double,
        assetSymbol: String = "USDC",
        country: String = "US",
        fiatCurrency: String = "USD"
    ) async throws -> CreateOfframpSessionResponse {
        guard fiatAmount > 0 else {
            throw CoinbaseError.invalidAmount
        }

        let request = CreateOfframpSessionRequest(
            walletAddress: walletAddress,
            fiatAmount: fiatAmount,
            assetSymbol: assetSymbol,
            country: country,
            fiatCurrency: fiatCurrency
        )

        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)
            guard let requestDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                throw CoinbaseError.unknownError
            }

            let result = try await firebaseClient.call(
                "createCoinbaseOfframpSession",
                data: requestDict,
                timeout: 30
            )

            guard let responseData = result.data as? [String: Any] else {
                throw CoinbaseError.sessionCreationFailed("Invalid response format")
            }

            let responseJson = try JSONSerialization.data(withJSONObject: responseData)
            let decoder = JSONDecoder()
            let response = try decoder.decode(CreateOfframpSessionResponse.self, from: responseJson)

            return response
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw CoinbaseError.unauthenticated
                case .invalidArgument:
                    throw CoinbaseError.invalidAmount
                case .unavailable:
                    throw CoinbaseError.sessionCreationFailed("Service temporarily unavailable")
                case .failedPrecondition:
                    throw CoinbaseError.sessionCreationFailed("Insufficient balance")
                default:
                    throw CoinbaseError.sessionCreationFailed(error.localizedDescription)
                }
            }
            throw CoinbaseError.networkError(error)
        }
    }

    // MARK: - Status Polling

    /// Gets the current status of a Coinbase transfer
    /// - Parameters:
    ///   - sessionId: The session ID
    ///   - sessionType: Type of session (onramp or offramp)
    /// - Returns: Transfer status details
    func getTransferStatus(
        sessionId: String,
        sessionType: String
    ) async throws -> CoinbaseTransferStatus {
        let data: [String: Any] = [
            "sessionId": sessionId,
            "sessionType": sessionType
        ]

        do {
            let result = try await firebaseClient.call(
                "getCoinbaseTransferStatus",
                data: data,
                timeout: 15
            )

            guard let responseData = result.data as? [String: Any] else {
                throw CoinbaseError.statusCheckFailed("Invalid response format")
            }

            let responseJson = try JSONSerialization.data(withJSONObject: responseData)
            let decoder = JSONDecoder()
            let response = try decoder.decode(CoinbaseTransferStatus.self, from: responseJson)

            return response
        } catch let error as NSError {
            if error.domain == FunctionsErrorDomain {
                let code = FunctionsErrorCode(rawValue: error.code)
                switch code {
                case .unauthenticated:
                    throw CoinbaseError.unauthenticated
                case .notFound:
                    throw CoinbaseError.statusCheckFailed("Session not found")
                case .permissionDenied:
                    throw CoinbaseError.statusCheckFailed("Access denied")
                default:
                    throw CoinbaseError.statusCheckFailed(error.localizedDescription)
                }
            }
            throw CoinbaseError.networkError(error)
        }
    }
}

// MARK: - Transfer Status Model

/// Status response for a Coinbase transfer
struct CoinbaseTransferStatus: Codable {
    let sessionId: String
    let coinbaseSessionId: String
    let status: String
    let walletAddress: String?
    let depositAddress: String?
    let assetSymbol: String
    let fiatAmount: Double?
    let cryptoAmount: Double?
    let transactionHash: String?
    let createdAt: String
    let updatedAt: String
    let completedAt: String?
    let failureReason: String?

    var isCompleted: Bool {
        status == "completed"
    }

    var isFailed: Bool {
        status == "failed"
    }

    var isPending: Bool {
        ["created", "pending", "awaiting_crypto", "processing"].contains(status)
    }
}
