import Foundation
import FirebaseRemoteConfig
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "RemoteConfig")

/// Manager for Firebase Remote Config
/// Provides secure access to remote configuration values like API keys
@MainActor
class RemoteConfigManager: ObservableObject {
    static let shared = RemoteConfigManager()

    private let remoteConfig: RemoteConfig
    @Published private(set) var isFetched = false

    // MARK: - Remote Config Keys

    private enum ConfigKey: String {
        case heliusRpcUrl = "helius_rpc_url"
        case heliusApiKey = "helius_api_key"
        case enableSwaps = "enable_swaps"
        case enableCustomInstructions = "enable_custom_instructions"
        case maxTransactionRetries = "max_transaction_retries"
        case enableOnramp = "enable_onramp"
        case enableOfframp = "enable_offramp"
    }

    // MARK: - Default Values

    private let defaults: [String: NSObject] = [
        ConfigKey.heliusRpcUrl.rawValue: "" as NSObject,
        ConfigKey.heliusApiKey.rawValue: "" as NSObject,
        ConfigKey.enableSwaps.rawValue: true as NSObject,
        ConfigKey.enableCustomInstructions.rawValue: false as NSObject,
        ConfigKey.maxTransactionRetries.rawValue: 3 as NSObject,
        ConfigKey.enableOnramp.rawValue: true as NSObject,
        ConfigKey.enableOfframp.rawValue: true as NSObject,
    ]

    private init() {
        self.remoteConfig = RemoteConfig.remoteConfig()

        // Configure fetch settings
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600 // 1 hour in production
        #if DEBUG
        settings.minimumFetchInterval = 0 // No caching in debug
        #endif

        remoteConfig.configSettings = settings
        remoteConfig.setDefaults(defaults)

        logger.info("✅ RemoteConfigManager initialized")
    }

    // MARK: - Public API

    /// Fetch and activate remote config values
    func fetchAndActivate() async throws {
        logger.info("🔄 Fetching remote config...")

        let status = try await remoteConfig.fetchAndActivate()

        switch status {
        case .successFetchedFromRemote:
            logger.info("✅ Remote config fetched from server")
        case .successUsingPreFetchedData:
            logger.info("✅ Remote config using cached data")
        case .error:
            logger.error("❌ Remote config fetch failed")
            throw RemoteConfigError.fetchFailed
        @unknown default:
            logger.warning("⚠️ Unknown remote config status")
        }

        await MainActor.run {
            self.isFetched = true
        }
    }

    /// Get Helius RPC URL
    var heliusRpcUrl: String {
        let value = remoteConfig.configValue(forKey: ConfigKey.heliusRpcUrl.rawValue).stringValue ?? ""
        return value.isEmpty ? "" : value
    }

    /// Get Helius API key
    var heliusApiKey: String {
        let value = remoteConfig.configValue(forKey: ConfigKey.heliusApiKey.rawValue).stringValue ?? ""
        return value.isEmpty ? "" : value
    }

    /// Check if swaps are enabled
    var enableSwaps: Bool {
        return remoteConfig.configValue(forKey: ConfigKey.enableSwaps.rawValue).boolValue
    }

    /// Check if custom instructions are enabled
    var enableCustomInstructions: Bool {
        return remoteConfig.configValue(forKey: ConfigKey.enableCustomInstructions.rawValue).boolValue
    }

    /// Get maximum transaction retries
    var maxTransactionRetries: Int {
        return remoteConfig.configValue(forKey: ConfigKey.maxTransactionRetries.rawValue).numberValue.intValue
    }

    /// Check if Coinbase onramp is enabled
    var enableOnramp: Bool {
        return remoteConfig.configValue(forKey: ConfigKey.enableOnramp.rawValue).boolValue
    }

    /// Check if Coinbase offramp is enabled
    var enableOfframp: Bool {
        return remoteConfig.configValue(forKey: ConfigKey.enableOfframp.rawValue).boolValue
    }

    /// Check if remote config has been fetched
    var hasHeliusConfig: Bool {
        return !heliusRpcUrl.isEmpty
    }
}

// MARK: - Errors

enum RemoteConfigError: LocalizedError {
    case fetchFailed
    case notFetched

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch remote configuration"
        case .notFetched:
            return "Remote configuration not yet fetched"
        }
    }
}
