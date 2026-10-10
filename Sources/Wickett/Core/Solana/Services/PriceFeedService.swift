import Foundation
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "PriceFeedService")

/// Service for fetching and caching token prices
@MainActor
class PriceFeedService: ObservableObject {
    static let shared = PriceFeedService()

    @Published var prices: [String: Decimal] = [:]  // symbol → USD price
    @Published var changes24h: [String: Decimal] = [:] // symbol → 24h change %

    private var lastUpdate: Date?
    private let cacheExpiration: TimeInterval = 30 // 30 seconds
    private var refreshTask: Task<Void, Never>?

    // CoinGecko ID Mapping - computed from TokenRegistry (single source of truth)
    private var symbolToCoingeckoId: [String: String] {
        Dictionary(uniqueKeysWithValues:
            TokenRegistry.allTokens.compactMap { token in
                token.coingeckoId.map { (token.symbol, $0) }
            }
        )
    }

    // DexScreener tokens - tokens without CoinGecko IDs, computed from TokenRegistry
    private var symbolToMintAddress: [String: String] {
        Dictionary(uniqueKeysWithValues:
            TokenRegistry.allTokens.compactMap { token -> (String, String)? in
                guard token.coingeckoId == nil, let mint = token.mint else { return nil }
                return (token.symbol, mint)
            }
        )
    }

    private init() {}

    // MARK: - Public API

    /// Get current price for a token
    func getPrice(for symbol: String) -> Decimal {
        return prices[symbol] ?? 0
    }

    /// Get 24h change for a token
    func getChange24h(for symbol: String) -> Decimal? {
        return changes24h[symbol]
    }

    /// Refresh prices if cache is expired
    func refreshIfNeeded() async {
        if shouldRefresh() {
            await refreshPrices()
        }
    }

    /// Force refresh prices
    func refreshPrices() async {
        logger.info("🔄 Refreshing token prices...")

        do {
            // Fetch from CoinGecko (main tokens)
            let coingeckoPrices = try await fetchPricesFromCoinGecko()

            // Fetch from DexScreener (xStock tokens not on CoinGecko)
            let dexScreenerPrices = await fetchPricesFromDexScreener()

            await MainActor.run {
                // Merge prices from both sources
                self.prices = coingeckoPrices.prices.merging(dexScreenerPrices.prices) { _, new in new }
                self.changes24h = coingeckoPrices.changes.merging(dexScreenerPrices.changes) { _, new in new }
                self.lastUpdate = Date()
            }

            logger.info("✅ Prices updated: SOL=$\(coingeckoPrices.prices["SOL"] ?? 0), GOLD=$\(dexScreenerPrices.prices["GOLD"] ?? 0)")
        } catch {
            logger.error("❌ Failed to fetch prices: \(error.localizedDescription)")
        }
    }

    /// Fetch historical prices for a token (7 days)
    /// Returns array of [Timestamp: Price]
    func fetchHistoricalPrices(for symbol: String, days: Int = 7) async throws -> [(Date, Decimal)] {
        guard let id = symbolToCoingeckoId[symbol] else {
            logger.warning("⚠️ No CoinGecko ID for \(symbol)")
            return []
        }

        // CoinGecko Market Chart API
        let urlString = "https://api.coingecko.com/api/v3/coins/\(id)/market_chart?vs_currency=usd&days=\(days)"

        guard let url = URL(string: urlString) else {
            throw PriceFeedError.invalidURL
        }

        // Add delay to avoid rate limiting if called in loop
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PriceFeedError.invalidResponse
        }

        // Parse Response
        // Format: { "prices": [ [timestamp, price], [timestamp, price] ... ] }
        struct MarketChart: Decodable {
            let prices: [[Double]]
        }

        let chartData = try JSONDecoder().decode(MarketChart.self, from: data)

        return chartData.prices.map { point in
            let timestamp = Date(timeIntervalSince1970: point[0] / 1000)
            let price = Decimal(point[1])
            return (timestamp, price)
        }
    }

    /// Start automatic price updates (every 60s)
    func startAutomaticUpdates() {
        stopAutomaticUpdates()

        refreshTask = Task {
            while !Task.isCancelled {
                await refreshPrices()

                // Wait 60 seconds before next update
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }

        logger.info("🔄 Started automatic price updates (60s interval)")
    }

    /// Stop automatic price updates
    func stopAutomaticUpdates() {
        refreshTask?.cancel()
        refreshTask = nil
        logger.info("⏸️ Stopped automatic price updates")
    }

    // MARK: - Private Helpers

    private func shouldRefresh() -> Bool {
        guard let lastUpdate = lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > cacheExpiration
    }

    /// Fetch prices from DexScreener for xStock tokens
    private func fetchPricesFromDexScreener() async -> (prices: [String: Decimal], changes: [String: Decimal]) {
        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]

        // Batch fetch all tokens in one request
        let mintAddresses = symbolToMintAddress.values.joined(separator: ",")
        let urlString = "https://api.dexscreener.com/latest/dex/tokens/\(mintAddresses)"

        guard let url = URL(string: urlString) else {
            logger.warning("⚠️ Invalid DexScreener URL")
            return (prices, changes)
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                logger.warning("⚠️ DexScreener returned non-200 status")
                return (prices, changes)
            }

            // Parse DexScreener response
            struct DexScreenerResponse: Decodable {
                let pairs: [DexPair]?
            }

            struct DexPair: Decodable {
                let baseToken: BaseToken
                let priceUsd: String?
                let priceChange: PriceChange?
            }

            struct BaseToken: Decodable {
                let address: String
                let symbol: String
            }

            struct PriceChange: Decodable {
                let h24: Double?
            }

            let dexResponse = try JSONDecoder().decode(DexScreenerResponse.self, from: data)

            // Map addresses back to symbols and extract prices
            let addressToSymbol = Dictionary(uniqueKeysWithValues: symbolToMintAddress.map { ($1, $0) })

            for pair in dexResponse.pairs ?? [] {
                let address = pair.baseToken.address
                if let symbol = addressToSymbol[address],
                   let priceString = pair.priceUsd,
                   let priceDouble = Double(priceString) {
                    // Only use the first (highest liquidity) pair for each token
                    if prices[symbol] == nil {
                        prices[symbol] = Decimal(priceDouble)
                        if let change24h = pair.priceChange?.h24 {
                            changes[symbol] = Decimal(change24h)
                        }
                        logger.info("   \(symbol): $\(priceDouble)")
                    }
                }
            }

            logger.info("✅ DexScreener: fetched \(prices.count) xStock prices")
        } catch {
            logger.warning("⚠️ DexScreener fetch failed: \(error.localizedDescription)")
        }

        return (prices, changes)
    }

    private func fetchPricesFromCoinGecko() async throws -> (prices: [String: Decimal], changes: [String: Decimal]) {
        // CoinGecko API endpoint (free tier)
        let coingeckoIds = symbolToCoingeckoId.values.joined(separator: ",")

        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=\(coingeckoIds)&vs_currencies=usd&include_24hr_change=true"

        guard let url = URL(string: urlString) else {
            throw PriceFeedError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PriceFeedError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw PriceFeedError.httpError(statusCode: httpResponse.statusCode)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Double]]

        guard let json = json else {
            throw PriceFeedError.invalidData
        }

        var prices: [String: Decimal] = [:]
        var changes: [String: Decimal] = [:]

        // Map back from CoinGecko ID to Symbol
        for (symbol, id) in symbolToCoingeckoId {
            if let coinData = json[id] {
                prices[symbol] = coinData["usd"].map { Decimal($0) } ?? 0
                changes[symbol] = coinData["usd_24h_change"].map { Decimal($0) }
            }
        }

        return (prices, changes)
    }
}

// MARK: - Errors

enum PriceFeedError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid price feed URL"
        case .invalidResponse:
            return "Invalid response from price feed"
        case .httpError(let statusCode):
            return "Price feed error: HTTP \(statusCode)"
        case .invalidData:
            return "Invalid price data format"
        }
    }
}
