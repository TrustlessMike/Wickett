import Foundation
import SwiftUI
import OSLog

/// Service for fetching token metadata and logos from Jupiter API
actor TokenMetadataService {
    static let shared = TokenMetadataService()

    private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "TokenMetadata")
    private let cache = NSCache<NSString, UIImage>()

    // Jupiter's token list - the canonical source for Solana token metadata
    private let jupiterTokenListURL = "https://token.jup.ag/all"

    private var tokenMetadata: [String: TokenMetadata] = [:]
    private var isInitialized = false

    /// Hardcoded fallback URLs for common tokens (in case Jupiter API is unreachable)
    private static let fallbackMetadata: [String: TokenMetadata] = [
        "native": TokenMetadata(
            address: "native",
            chainId: 101,
            decimals: 9,
            name: "Solana",
            symbol: "SOL",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "solana")
        ),

        "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": TokenMetadata(
            address: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
            chainId: 101,
            decimals: 6,
            name: "USD Coin",
            symbol: "USDC",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "usd-coin")
        ),

        "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": TokenMetadata(
            address: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
            chainId: 101,
            decimals: 6,
            name: "Tether USD",
            symbol: "USDT",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "tether")
        ),

        "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": TokenMetadata(
            address: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
            chainId: 101,
            decimals: 5,
            name: "Bonk",
            symbol: "BONK",
            logoURI: "https://arweave.net/hQiPZOsRZXGXBJd_82PhVdlM_hACsT_q6wqwf5cSY7I",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "bonk")
        ),

        "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh": TokenMetadata(
            address: "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh",
            chainId: 101,
            decimals: 8,
            name: "Wrapped Bitcoin",
            symbol: "wBTC",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "wrapped-bitcoin")
        ),

        "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs": TokenMetadata(
            address: "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs",
            chainId: 101,
            decimals: 8,
            name: "Wrapped Ethereum",
            symbol: "wETH",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "weth")
        ),

        "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN": TokenMetadata(
            address: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
            chainId: 101,
            decimals: 6,
            name: "Jupiter",
            symbol: "JUP",
            logoURI: "https://static.jup.ag/jup/icon.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "jupiter-exchange-solana")
        ),

        "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R": TokenMetadata(
            address: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
            chainId: 101,
            decimals: 6,
            name: "Raydium",
            symbol: "RAY",
            logoURI: "https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R/logo.png",
            tags: ["verified"],
            extensions: TokenMetadata.Extensions(coingeckoId: "raydium")
        ),

        "GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A": TokenMetadata(
            address: "GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A",
            chainId: 101,
            decimals: 9,
            name: "Gold",
            symbol: "GOLD",
            logoURI: "https://static.jup.ag/tokens/GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A.png",
            tags: nil,
            extensions: nil
        ),
    ]

    private init() {
        cache.countLimit = 100 // Cache up to 100 token images
        // Load fallback metadata
        tokenMetadata = Self.fallbackMetadata
    }

    /// Jupiter API response wrapper
    struct JupiterTokenListResponse: Codable {
        let timestamp: String?
        let tokens: [TokenMetadata]
    }

    /// Token metadata from Jupiter API
    struct TokenMetadata: Codable {
        let address: String
        let chainId: Int
        let decimals: Int
        let name: String
        let symbol: String
        let logoURI: String?
        let tags: [String]?
        let extensions: Extensions?

        struct Extensions: Codable {
            let coingeckoId: String?
            let tags: [String]?
            let token2022: [String]?

            // Regular initializer for creating instances manually
            init(coingeckoId: String? = nil, tags: [String]? = nil, token2022: [String]? = nil) {
                self.coingeckoId = coingeckoId
                self.tags = tags
                self.token2022 = token2022
            }

            // Use CodingKeys to allow flexible decoding
            private enum CodingKeys: String, CodingKey {
                case coingeckoId
                case tags
                case token2022
            }

            // Custom decoder to ignore unknown fields
            init(from decoder: Decoder) throws {
                let container = try? decoder.container(keyedBy: CodingKeys.self)
                coingeckoId = try? container?.decodeIfPresent(String.self, forKey: .coingeckoId)
                tags = try? container?.decodeIfPresent([String].self, forKey: .tags)
                token2022 = try? container?.decodeIfPresent([String].self, forKey: .token2022)
            }
        }
    }

    /// Initialize by fetching the token list
    func initialize() async {
        guard !isInitialized else { return }

        do {
            logger.info("🔄 Fetching Jupiter token list...")

            guard let url = URL(string: jupiterTokenListURL) else {
                logger.error("❌ Invalid Jupiter token list URL")
                return
            }

            let (data, _) = try await URLSession.shared.data(from: url)

            // Try to decode with wrapper first (newer Jupiter API format)
            let tokens: [TokenMetadata]
            if let response = try? JSONDecoder().decode(JupiterTokenListResponse.self, from: data) {
                tokens = response.tokens
                logger.info("✅ Decoded Jupiter response with timestamp: \(response.timestamp ?? "unknown")")
            } else {
                // Fallback to direct array decoding (older format)
                tokens = try JSONDecoder().decode([TokenMetadata].self, from: data)
                logger.info("✅ Decoded Jupiter response as direct array")
            }

            // Build lookup dictionary by mint address (overwrites fallback metadata with fresh data)
            for token in tokens {
                tokenMetadata[token.address] = token
            }

            isInitialized = true
            logger.info("✅ Loaded \(tokens.count) tokens from Jupiter (fallback metadata available for common tokens)")

        } catch {
            logger.error("❌ Failed to fetch token list: \(error.localizedDescription)")
            logger.info("ℹ️ Using fallback metadata for \(self.tokenMetadata.count) common tokens")
            // Don't fail completely - we have fallback metadata
            isInitialized = true
        }
    }

    /// Get logo URL for a token
    func getLogoURL(for token: SolanaToken) async -> String? {
        if !isInitialized {
            await initialize()
        }

        // For native SOL
        if token.mint == nil {
            return tokenMetadata["native"]?.logoURI
        }

        // For SPL tokens
        guard let mint = token.mint else { return nil }
        return tokenMetadata[mint]?.logoURI
    }

    /// Download and cache token image
    func fetchImage(for token: SolanaToken) async -> UIImage? {
        // Check cache first
        let cacheKey = (token.mint ?? "native") as NSString
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        // 1. Try Local Asset Catalog first (Fastest & Offline)
        if let localImage = await loadLocalAsset(for: token.symbol) {
            logger.info("✅ Loaded local asset for \(token.symbol)")
            cache.setObject(localImage, forKey: cacheKey)
            return localImage
        }

        // 2. Fallback to Remote URL
        guard let logoURL = await getLogoURL(for: token),
              let url = URL(string: logoURL) else {
            logger.warning("⚠️ No logo URL for \(token.symbol)")
            return nil
        }

        do {
            logger.info("🔄 Downloading logo for \(token.symbol) from \(logoURL)")

            let (data, _) = try await URLSession.shared.data(from: url)

            guard let image = UIImage(data: data) else {
                logger.error("❌ Failed to decode image for \(token.symbol)")
                return nil
            }

            // Cache the image
            cache.setObject(image, forKey: cacheKey)
            logger.info("✅ Cached logo for \(token.symbol)")

            return image

        } catch {
            logger.error("❌ Failed to download logo for \(token.symbol): \(error.localizedDescription)")
            return nil
        }
    }

    /// Try to load image from local asset catalog
    @MainActor
    private func loadLocalAsset(for symbol: String) -> UIImage? {
        // Default convention: "TokenSYMBOL" (e.g. "TokenSOL")
        // Fallback: "symbol" (lowercase)
        // Fallback: "SYMBOL" (uppercase)

        // Special mappings for xStock tokens
        switch symbol.uppercased() {
        case "AAPL": return UIImage(named: "TokenAAPLX")
        case "TSLA": return UIImage(named: "TokenTSLAX")
        case "NVDA": return UIImage(named: "TokenNVDAX")
        case "MSFT": return UIImage(named: "TokenMSFTX")
        case "AMZN": return UIImage(named: "TokenAMZNx")
        case "SOL": return UIImage(named: "TokenSOL")
        case "USDC": return UIImage(named: "TokenUSDC")
        case "USDT": return UIImage(named: "TokenUSDT")
        case "BONK": return UIImage(named: "TokenBONK")
        case "JUP": return UIImage(named: "TokenJUP")
        case "RAY": return UIImage(named: "TokenRAY")
        case "WETH": return UIImage(named: "TokenWETH")
        case "WBTC": return UIImage(named: "TokenWBTC")
        case "GOLD": return UIImage(named: "TokenGOLD")
        default: break
        }

        // General fallback
        if let image = UIImage(named: "Token\(symbol.uppercased())") {
            return image
        }
        if let image = UIImage(named: symbol.lowercased()) {
            return image
        }

        return nil
    }

    /// Preload images for common tokens
    func preloadCommonTokens() async {
        logger.info("🔄 Preloading common token logos...")

        await withTaskGroup(of: Void.self) { group in
            for token in TokenRegistry.allTokens {
                group.addTask {
                    _ = await self.fetchImage(for: token)
                }
            }
        }

        logger.info("✅ Finished preloading token logos")
    }
}
