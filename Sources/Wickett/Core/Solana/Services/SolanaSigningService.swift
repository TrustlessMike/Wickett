import Foundation
import PrivySDK
import SolanaSwift
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "SolanaSigningService")

/// Service for signing Solana transactions using Privy embedded wallet
@MainActor
class SolanaSigningService {
    static let shared = SolanaSigningService()

    private let hybridPrivyService = HybridPrivyService.shared

    private init() {
        logger.info("✅ SolanaSigningService initialized")
    }

    // MARK: - Public API

    /// Sign a partially-signed Solana transaction with the user's embedded wallet
    /// - Parameter partialTransaction: Base64-encoded partial transaction (with fee payer signature only)
    /// - Returns: Base64-encoded fully-signed transaction (with both fee payer and user signatures)
    func signTransaction(_ partialTransaction: String) async throws -> String {
        logger.info("✍️ Starting transaction signing process...")

        do {
            // Step 1: Deserialize the partial transaction
            logger.info("📦 Deserializing partial transaction...")
            guard let transactionData = Data(base64Encoded: partialTransaction) else {
                throw SolanaSigningError.invalidTransaction
            }

            let versionedTransaction = try VersionedTransaction.deserialize(data: transactionData)
            logger.info("✅ Transaction deserialized")

            // Step 2: Extract the message to sign
            logger.info("📝 Extracting message from transaction...")
            let messageData: Data
            switch versionedTransaction.message {
            case .legacy(let legacyMessage):
                messageData = Data(try legacyMessage.serialize())
                logger.info("📋 Using legacy message format")
            case .v0(let messageV0):
                messageData = Data(try messageV0.serialize())
                logger.info("📋 Using v0 message format")
            }

            let messageToSign = messageData.base64EncodedString()
            logger.info("✅ Message extracted, length: \(messageToSign.count) characters")

            // Step 3: Sign the message with Privy (this triggers user approval UI)
            logger.info("✍️ Requesting signature from Privy...")
            let signingResult = try await hybridPrivyService.signMessageForSponsorship(messageToSign)

            logger.info("✅ Signature received from Privy")
            logger.info("💼 Wallet address: \(signingResult.walletAddress)")

            // Step 4: Add the user signature to the transaction
            logger.info("🔧 Adding user signature to transaction...")
            var completeTransaction = versionedTransaction

            let userPublicKey = try PublicKey(string: signingResult.walletAddress)
            guard let signatureData = Data(base64Encoded: signingResult.signature) else {
                throw SolanaSigningError.invalidSignature
            }

            try completeTransaction.addSignature(publicKey: userPublicKey, signature: signatureData)
            logger.info("✅ User signature added to transaction")

            // Step 5: Serialize the fully-signed transaction
            logger.info("📦 Serializing fully-signed transaction...")
            let signedTransactionData = Data(try completeTransaction.serialize())
            let serializedBase64 = signedTransactionData.base64EncodedString()

            logger.info("✅ Fully-signed transaction created, length: \(serializedBase64.count) characters")
            return serializedBase64

        } catch let error as SolanaSigningError {
            logger.error("❌ Transaction signing failed: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("❌ Transaction signing failed: \(error.localizedDescription)")
            throw SolanaSigningError.signingFailed(error.localizedDescription)
        }
    }

}

// MARK: - Errors

enum SolanaSigningError: LocalizedError {
    case userNotAuthenticated
    case noSolanaWallet
    case providerNotAvailable
    case signingFailed(String)
    case invalidTransaction
    case invalidSignature

    var errorDescription: String? {
        switch self {
        case .userNotAuthenticated:
            return "Please sign in to continue"
        case .noSolanaWallet:
            return "No Solana wallet found. Please create a wallet first."
        case .providerNotAvailable:
            return "Unable to access wallet provider"
        case .signingFailed(let message):
            return "Transaction signing failed: \(message)"
        case .invalidTransaction:
            return "Invalid transaction format"
        case .invalidSignature:
            return "Invalid signature format"
        }
    }
}
