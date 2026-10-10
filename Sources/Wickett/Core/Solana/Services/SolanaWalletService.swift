import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "SolanaWallet")

/// Orchestrates Solana wallet operations - balance fetching, state management
@MainActor
class SolanaWalletService: ObservableObject {
    static let shared = SolanaWalletService()

    // MARK: - Published State

    @Published var balances: [TokenBalance] = []
    @Published var isLoading = false
    @Published var error: WalletError?
    @Published var lastUpdated: Date?

    // MARK: - Dependencies

    private let heliusService = HeliusService.shared
    private let priceFeedService = PriceFeedService.shared
    private let remoteConfig = RemoteConfigManager.shared

    // MARK: - Configuration

    private let autoRefreshInterval: TimeInterval = 60 // 60 seconds
    private var refreshTimer: Timer?

    private init() {
        logger.info("✅ SolanaWalletService initialized")
    }

    // MARK: - Public API

    /// Initialize wallet service and fetch initial data
    func initialize() async {
        logger.info("🔄 Initializing wallet service...")

        // Ensure remote config is fetched
        if !remoteConfig.isFetched {
            do {
                try await remoteConfig.fetchAndActivate()
            } catch {
                logger.error("❌ Failed to fetch remote config: \(error.localizedDescription)")
                await MainActor.run {
                    self.error = .configurationError
                }
                return
            }
        }

        // Start price feed
        priceFeedService.startAutomaticUpdates()

        logger.info("✅ Wallet service initialized")
    }

    /// Refresh all balances and prices
    /// - Parameter force: If true, cancels any in-progress refresh and starts a new one
    func refreshBalances(walletAddress: String, force: Bool = false) async {
        if isLoading {
            if force {
                logger.info("🔄 Force refresh requested, restarting...")
            } else {
                logger.info("⏭️ Already loading, skipping refresh")
                return
            }
        }

        isLoading = true
        error = nil

        logger.info("🔄 Refreshing balances for \(walletAddress.prefix(8))...")

        do {
            // Fetch SOL balance, SPL balances, and prices in PARALLEL
            async let solBalanceTask = heliusService.getSOLBalance(walletAddress: walletAddress)
            async let splBalancesTask = heliusService.getSPLTokenBalances(walletAddress: walletAddress)
            async let pricesTask: () = priceFeedService.refreshIfNeeded()

            // Wait for all to complete
            let (solBalance, splBalances, _) = try await (solBalanceTask, splBalancesTask, pricesTask)

            // Quick price validation (no 1 second delay - prices should be cached by now)
            let solPrice = priceFeedService.getPrice(for: "SOL")
            if solPrice == 0 && solBalance > 0 {
                logger.warning("⚠️ SOL price is 0 despite having balance - will use cached price")
            }

            // Convert to TokenBalance objects
            var newBalances: [TokenBalance] = []

            // Add SOL
            let solPriceRefreshed = priceFeedService.getPrice(for: "SOL")
            let solChange = priceFeedService.getChange24h(for: "SOL")

            if solPriceRefreshed == 0 {
                logger.warning("⚠️ SOL price still 0 after refresh - using balance without USD value")
            }

            newBalances.append(TokenBalance(
                token: TokenRegistry.SOL,
                lamports: solBalance,
                usdPrice: solPriceRefreshed,
                change24h: solChange
            ))

            // Add SPL tokens (only ones in our registry)
            for splBalance in splBalances {
                guard let token = TokenRegistry.token(forMint: splBalance.mint) else {
                    // Skip tokens not in our registry
                    continue
                }

                let price = priceFeedService.getPrice(for: token.symbol)
                let change = priceFeedService.getChange24h(for: token.symbol)

                if price == 0 && splBalance.amount > 0 {
                    logger.warning("⚠️ \(token.symbol) price is 0 despite having balance")
                }

                newBalances.append(TokenBalance(
                    token: token,
                    lamports: splBalance.amount,
                    usdPrice: price,
                    change24h: change
                ))
            }

            // Sort by USD value (descending)
            newBalances.sort { $0.usdValue > $1.usdValue }

            self.balances = newBalances
            self.lastUpdated = Date()
            self.isLoading = false

            // Update portfolio history
            let manager = PortfolioHistoryManager.shared
            manager.addDataPoint(value: self.totalUSDValue)

            // Trigger backfill if needed
            if manager.history.count < 10 {
                Task {
                    await manager.backfillHistory(balances: newBalances)
                }
            }

            logger.info("✅ Refreshed \(newBalances.count) token balances")

        } catch is CancellationError {
            logger.info("🚫 Refresh cancelled")
            isLoading = false
        } catch {
            logger.error("❌ Failed to refresh balances: \(error.localizedDescription)")
            self.error = .fetchError(error.localizedDescription)
            isLoading = false
        }
    }

    /// Get total portfolio value in USD
    var totalUSDValue: Decimal {
        return balances.reduce(0) { $0 + $1.usdValue }
    }

    /// Get total 24h change percentage
    var total24hChange: Decimal? {
        let totalValue = totalUSDValue
        guard totalValue > 0 else { return nil }

        var totalChange: Decimal = 0
        var hasChanges = false

        for balance in balances {
            if let change = balance.change24h {
                // Weight change by portfolio percentage
                let weight = balance.usdValue / totalValue
                totalChange += change * weight
                hasChanges = true
            }
        }

        return hasChanges ? totalChange : nil
    }

    /// Start automatic background refresh
    func startAutoRefresh(walletAddress: String) {
        stopAutoRefresh()

        logger.info("🔄 Starting auto-refresh every \(self.autoRefreshInterval)s")

        refreshTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only refresh if not already loading to prevent concurrent refreshes
                guard !self.isLoading else {
                    logger.info("⏭️ Skipping auto-refresh - already loading")
                    return
                }
                await self.refreshBalances(walletAddress: walletAddress)
            }
        }
    }

    /// Stop automatic background refresh
    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        logger.info("⏹️ Stopped auto-refresh")
    }

    /// Clear all balances and state
    func clear() {
        stopAutoRefresh()
        balances = []
        error = nil
        lastUpdated = nil
        isLoading = false
        logger.info("🧹 Cleared wallet state")
    }
}

// MARK: - Errors

enum WalletError: LocalizedError, Equatable {
    case configurationError
    case fetchError(String)
    case invalidWalletAddress

    static func == (lhs: WalletError, rhs: WalletError) -> Bool {
        switch (lhs, rhs) {
        case (.configurationError, .configurationError),
             (.invalidWalletAddress, .invalidWalletAddress):
            return true
        case let (.fetchError(lhsMessage), .fetchError(rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .configurationError:
            return "Failed to load wallet configuration"
        case .fetchError(let errorMessage):
            return "Failed to fetch balances: \(errorMessage)"
        case .invalidWalletAddress:
            return "Invalid wallet address"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .configurationError:
            return "Please check your internet connection and try again"
        case .fetchError:
            return "Pull to refresh to try again"
        case .invalidWalletAddress:
            return "Please check your wallet address"
        }
    }
}

// MARK: - Portfolio History Manager

struct PortfolioDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let value: Decimal

    init(value: Decimal, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.value = value
    }
}

@MainActor
class PortfolioHistoryManager: ObservableObject {
    static let shared = PortfolioHistoryManager()

    @Published var history: [PortfolioDataPoint] = []
    @Published var isBackfilling = false

    private var currentUserId: String?

    private var storageKey: String {
        "portfolio_history_v2_\(currentUserId ?? "anonymous")"
    }

    // We'll store hourly data points for the chart
    private let maxDataPoints = 168 // 7 days * 24 hours

    private init() {
        // Don't load history on init - wait for switchUser to be called
    }

    // MARK: - User Management

    /// Switch to a specific user's history
    func switchUser(userId: String) {
        guard userId != currentUserId else { return }
        currentUserId = userId
        loadHistory()
    }

    /// Clear history (call on sign-out)
    func clearHistory() {
        history = []
        currentUserId = nil
    }

    // MARK: - Public API

    /// Add a live data point (e.g., when app opens)
    func addDataPoint(value: Decimal) {
        // If we have no history, or the last point is old, add it
        guard value > 0 else { return }

        // If we are currently backfilling, don't add live points yet to avoid conflict
        guard !isBackfilling else { return }

        let now = Date()

        if let last = history.last {
            // If less than 15 mins passed, just update the last point instead of adding new one
            if now.timeIntervalSince(last.timestamp) < 900 {
                history[history.count - 1] = PortfolioDataPoint(value: value, timestamp: now)
                saveHistory()
                return
            }
        }

        let point = PortfolioDataPoint(value: value, timestamp: now)
        history.append(point)

        // Prune if too many
        if history.count > maxDataPoints {
            history.removeFirst(history.count - maxDataPoints)
        }

        saveHistory()
    }

    /// Rebuild history based on current holdings (Proxy Method)
    /// This simulates what the portfolio was worth over the last 7 days
    func backfillHistory(balances: [TokenBalance]) async {
        // Only backfill if history is empty or very short
        guard history.count < 10 else { return }
        guard !balances.isEmpty else { return }

        isBackfilling = true

        // 1. Fetch history for each token
        var tokenHistories: [String: [(Date, Decimal)]] = [:]

        for balance in balances {
            // Only fetch for significant holdings (> $1) to save API calls
            if balance.usdValue > 1.0 {
                do {
                    let prices = try await PriceFeedService.shared.fetchHistoricalPrices(for: balance.token.symbol)
                    tokenHistories[balance.token.symbol] = prices
                } catch {
                    // Skip tokens where historical data fetch fails
                }
            }
        }

        // 2. Combine histories
        // We need to align timestamps. CoinGecko returns hourly points roughly.
        // We'll iterate through the timestamps of the first token (usually SOL)
        // and sum up values of all other tokens at that approximate time.

        guard let baseHistory = tokenHistories.first?.value else {
            isBackfilling = false
            return
        }

        var newHistory: [PortfolioDataPoint] = []

        for (timestamp, _) in baseHistory {
            var totalValue: Decimal = 0

            for balance in balances {
                let symbol = balance.token.symbol
                let amount = balance.amount // Current amount (Assumed constant)

                if let history = tokenHistories[symbol] {
                    // Find price closest to this timestamp
                    // (Simple optimization: just finding first match since arrays are sorted)
                    if let pricePoint = history.first(where: { abs($0.0.timeIntervalSince(timestamp)) < 3600 }) {
                        totalValue += amount * pricePoint.1
                    } else {
                        // Fallback to current price if missing (shouldn't happen often)
                        totalValue += balance.usdValue
                    }
                } else {
                    // If we didn't fetch history (small holding), just add constant current value
                    totalValue += balance.usdValue
                }
            }

            if totalValue > 0 {
                newHistory.append(PortfolioDataPoint(value: totalValue, timestamp: timestamp))
            }
        }

        // 3. Save
        await MainActor.run {
            // Sort by date just in case
            self.history = newHistory.sorted(by: { $0.timestamp < $1.timestamp })
            self.isBackfilling = false
            self.saveHistory()
        }
    }

    // MARK: - Private Helpers

    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            // Silently fail - portfolio history is non-critical
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }

        do {
            history = try JSONDecoder().decode([PortfolioDataPoint].self, from: data)

            // Sanitize: remove invalid or zero values that might have slipped in
            let originalCount = history.count
            history.removeAll { $0.value <= 0.000001 }

            // Also remove if the last point is significantly lower (e.g. >99% drop) than the average of previous 3
            // This fixes "glitch" drops at the end of the chart
            if history.count >= 4 {
                let last = history.last!
                let prev3 = history.suffix(4).prefix(3)
                let avg = prev3.map { $0.value }.reduce(0, +) / Decimal(prev3.count)

                if avg > 0 && (last.value / avg) < 0.01 {
                    history.removeLast()
                }
            }

            if history.count != originalCount {
                saveHistory()
            }
        } catch {
            // Silently fail - portfolio history is non-critical
        }
    }

    /// Get normalized data for charting
    var chartData: [Double] {
        guard !history.isEmpty else { return [] }
        return history
            .map { NSDecimalNumber(decimal: $0.value).doubleValue }
            .filter { $0 > 0 }
    }
}
