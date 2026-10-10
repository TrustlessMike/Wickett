import Foundation
import OSLog
import FirebaseFunctions

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "DelegationManager")

/// Response from approveDelegationV2 (Privy-based)
struct ApproveDelegationV2Response {
    let delegationId: String
    let policyId: String
    let keyQuorumId: String
    let expiresAt: String
    let message: String
}

/// Manager for auto-convert delegation
@MainActor
class DelegationManager: ObservableObject {
    static let shared = DelegationManager()

    @Published var delegationStatus: DelegationStatusResponse?
    @Published var isLoading = false
    @Published var error: String?

    private let firebaseCallable = FirebaseCallableClient.shared
    private let privyService = HybridPrivyService.shared

    private init() {}

    // MARK: - Delegation Status

    /// Get current delegation status
    func fetchDelegationStatus() async {
        isLoading = true
        error = nil

        logger.info("📊 Fetching delegation status...")

        do {
            let result = try await firebaseCallable.call("getDelegationStatus", data: [:])

            guard let data = result.data as? [String: Any] else {
                throw DelegationError.invalidResponse
            }

            // Parse response
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let response = try JSONDecoder().decode(DelegationStatusResponse.self, from: jsonData)

            delegationStatus = response

            logger.info("✅ Delegation status fetched")
            logger.info("   Has delegation: \(response.hasActiveDelegation)")

            if let delegation = response.delegation {
                logger.info("   Total swaps: \(delegation.totalSwapsExecuted)")
                logger.info("   Total volume: $\(delegation.totalVolumeSwappedUsd)")
                logger.info("   Today's volume: $\(delegation.todayVolumeUsd)")
            }

            isLoading = false

        } catch {
            logger.error("❌ Failed to fetch delegation status: \(error)")
            self.error = "Failed to load delegation status"
            isLoading = false
        }
    }

    // MARK: - Approve Delegation

    /// Approve delegation with portfolio allocation (Privy V2)
    ///
    /// Flow:
    /// 1. Get user's Privy access token
    /// 2. Call approveDelegationV2 with token to create policy and update wallet in one step
    func approveDelegationV2(
        portfolio: [PortfolioAllocation],
        maxSwapAmountUsd: Double,
        dailyLimitUsd: Double,
        expirationDays: Int
    ) async throws -> ApproveDelegationV2Response {
        isLoading = true
        error = nil

        logger.info("📝 Creating Privy delegation...")
        logger.info("   Portfolio: \(portfolio.map { "\($0.symbol): \($0.percentage)%" }.joined(separator: ", "))")
        logger.info("   Max swap: $\(maxSwapAmountUsd)")
        logger.info("   Daily limit: $\(dailyLimitUsd)")
        logger.info("   Expires in: \(expirationDays) days")

        do {
            // Step 1: Get user's access token (JWT) from Privy
            // This is required because wallet policy updates need wallet owner authorization
            logger.info("🔑 Getting user access token...")
            guard let privyUser = try await privyService.getPrivyUser() else {
                throw DelegationError.transactionFailed("User not authenticated with Privy")
            }

            let accessToken = try await privyUser.getAccessToken()
            // Log token prefix for debugging (first 50 chars to see if it's a JWT format)
            let tokenPrefix = String(accessToken.prefix(50))
            logger.info("✅ Access token obtained: \(tokenPrefix)...")

            // Step 2: Call backend to create policy AND update wallet in one call
            let portfolioData = portfolio.map { $0.toDictionary() }

            let result = try await firebaseCallable.call(
                "approveDelegationV2",
                data: [
                    "portfolio": portfolioData,
                    "maxSwapAmountUsd": maxSwapAmountUsd,
                    "dailyLimitUsd": dailyLimitUsd,
                    "expirationDays": expirationDays,
                    "privyAccessToken": accessToken
                ]
            )

            guard let data = result.data as? [String: Any] else {
                throw DelegationError.invalidResponse
            }

            // Parse response
            let delegationId = data["delegationId"] as? String ?? ""
            let policyId = data["policyId"] as? String ?? ""
            let keyQuorumId = data["keyQuorumId"] as? String ?? ""
            let expiresAt = data["expiresAt"] as? String ?? ""
            let message = data["message"] as? String ?? "Auto-convert enabled!"

            logger.info("✅ Delegation created and activated!")
            logger.info("   Delegation ID: \(delegationId)")
            logger.info("   Policy ID: \(policyId)")
            logger.info("   Key quorum: \(keyQuorumId)")

            isLoading = false
            return ApproveDelegationV2Response(
                delegationId: delegationId,
                policyId: policyId,
                keyQuorumId: keyQuorumId,
                expiresAt: expiresAt,
                message: message
            )

        } catch {
            logger.error("❌ Failed to create Privy delegation: \(error)")
            self.error = "Failed to create delegation"
            isLoading = false
            throw error
        }
    }

    // MARK: - Revoke Delegation

    /// Revoke Privy V2 delegation (no transaction required)
    func revokeDelegationV2() async throws -> String {
        isLoading = true
        error = nil

        logger.info("🔒 Revoking Privy delegation...")

        do {
            let result = try await firebaseCallable.call("revokeDelegationV2", data: [:])

            guard let data = result.data as? [String: Any],
                  let message = data["message"] as? String else {
                throw DelegationError.invalidResponse
            }

            logger.info("✅ Delegation revoked successfully")

            isLoading = false
            return message

        } catch {
            logger.error("❌ Failed to revoke delegation: \(error)")
            self.error = "Failed to revoke delegation"
            isLoading = false
            throw error
        }
    }

    // MARK: - Portfolio Validation

    /// Validate portfolio allocation
    func validatePortfolio(_ portfolio: [PortfolioAllocation]) -> (isValid: Bool, error: String?) {
        // Check if empty
        if portfolio.isEmpty {
            return (false, "Portfolio must have at least one token")
        }

        // Check percentages sum to 100
        let total = portfolio.reduce(0) { $0 + $1.percentage }
        if abs(total - 100.0) > 0.01 {
            return (false, "Percentages must sum to 100% (currently \(String(format: "%.1f", total))%)")
        }

        // Check for duplicates
        let symbols = portfolio.map { $0.symbol }
        if symbols.count != Set(symbols).count {
            return (false, "Portfolio contains duplicate tokens")
        }

        // Check each percentage is valid
        for allocation in portfolio {
            if allocation.percentage <= 0 {
                return (false, "\(allocation.symbol) percentage must be greater than 0%")
            }
            if allocation.percentage > 100 {
                return (false, "\(allocation.symbol) percentage cannot exceed 100%")
            }
        }

        return (true, nil)
    }

    // MARK: - Helpers

    /// Format USD amount
    func formatUSD(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    /// Format percentage
    func formatPercentage(_ value: Double) -> String {
        return String(format: "%.1f%%", value)
    }

    /// Calculate days until expiration
    func daysUntilExpiration(expiresAt: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        guard let expirationDate = formatter.date(from: expiresAt) else {
            return nil
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: Date(), to: expirationDate)
        return components.day
    }
}

// MARK: - Errors

enum DelegationError: LocalizedError {
    case invalidResponse
    case invalidPortfolio(String)
    case transactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidPortfolio(let message):
            return message
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        }
    }
}
