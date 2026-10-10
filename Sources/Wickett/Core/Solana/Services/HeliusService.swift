import Foundation
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "HeliusService")

/// Service for interacting with Helius RPC API
/// Provides balance fetching and token account queries
class HeliusService {
    static let shared = HeliusService()

    private init() {}

    // MARK: - Balance Fetching

    /// Get SOL balance for a wallet address
    func getSOLBalance(walletAddress: String) async throws -> UInt64 {
        let rpcUrl = await RemoteConfigManager.shared.heliusRpcUrl
        guard !rpcUrl.isEmpty else {
            throw HeliusError.missingAPIKey
        }

        guard let url = URL(string: rpcUrl) else {
            throw HeliusError.invalidURL
        }

        let request = JSONRPCRequest(
            method: "getBalance",
            params: [walletAddress]
        )

        let response: JSONRPCResponse<BalanceResult> = try await sendRPCRequest(url: url, request: request)

        guard let balance = response.result?.value else {
            throw HeliusError.invalidResponse
        }

        logger.info("✅ SOL balance: \(balance) lamports")
        return balance
    }

    /// Get all SPL token balances for a wallet address
    /// Queries both SPL Token program and Token-2022 program
    func getSPLTokenBalances(walletAddress: String) async throws -> [TokenAccountInfo] {
        let rpcUrl = await RemoteConfigManager.shared.heliusRpcUrl
        guard !rpcUrl.isEmpty else {
            throw HeliusError.missingAPIKey
        }

        guard let url = URL(string: rpcUrl) else {
            throw HeliusError.invalidURL
        }

        // Query both token programs in parallel
        let tokenPrograms = [
            "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",  // Original SPL Token
            "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"   // Token-2022
        ]

        var allTokenAccounts: [TokenAccountInfo] = []

        for programId in tokenPrograms {
            let request = JSONRPCRequest(
                method: "getTokenAccountsByOwner",
                params: [
                    walletAddress,
                    ["programId": programId],
                    ["encoding": "jsonParsed"]
                ]
            )

            do {
                let response: JSONRPCResponse<TokenAccountsResult> = try await sendRPCRequest(url: url, request: request)

                guard let accounts = response.result?.value else {
                    continue
                }

                let tokenAccounts = accounts.compactMap { account -> TokenAccountInfo? in
                    guard let mint = account.account.data.parsed.info.mint,
                          let tokenAmount = account.account.data.parsed.info.tokenAmount,
                          let amountString = tokenAmount.amount,
                          let amount = UInt64(amountString),
                          let decimals = tokenAmount.decimals else {
                        return nil
                    }

                    return TokenAccountInfo(
                        mint: mint,
                        amount: amount,
                        decimals: decimals
                    )
                }

                allTokenAccounts.append(contentsOf: tokenAccounts)
            } catch {
                logger.warning("⚠️ Failed to fetch tokens for program \(programId): \(error.localizedDescription)")
            }
        }

        logger.info("✅ Found \(allTokenAccounts.count) SPL token accounts")
        return allTokenAccounts
    }

    // MARK: - Helper Methods

    private func sendRPCRequest<T: Decodable>(url: URL, request: JSONRPCRequest) async throws -> T {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HeliusError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("❌ RPC error: HTTP \(httpResponse.statusCode)")
            throw HeliusError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            logger.error("❌ Failed to decode response: \(error.localizedDescription)")
            throw HeliusError.decodingError(error)
        }
    }
}

// MARK: - RPC Models

private struct JSONRPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: [Any]

    enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)

        // Encode params as JSON array
        var paramsContainer = container.nestedUnkeyedContainer(forKey: .params)
        for param in params {
            if let string = param as? String {
                try paramsContainer.encode(string)
            } else if let dict = param as? [String: Any] {
                try paramsContainer.encode(AnyCodable(dict))
            }
        }
    }
}

private struct JSONRPCResponse<T: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int
    let result: T?
    let error: JSONRPCError?
}

private struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

private struct BalanceResult: Decodable {
    let context: Context
    let value: UInt64

    struct Context: Decodable {
        let slot: UInt64
    }
}

private struct TokenAccountsResult: Decodable {
    let context: Context
    let value: [TokenAccount]

    struct Context: Decodable {
        let slot: UInt64
    }
}

private struct TokenAccount: Decodable {
    let pubkey: String
    let account: Account

    struct Account: Decodable {
        let data: Data

        struct Data: Decodable {
            let parsed: Parsed

            struct Parsed: Decodable {
                let info: Info

                struct Info: Decodable {
                    let mint: String?
                    let owner: String?
                    let tokenAmount: TokenAmount?

                    struct TokenAmount: Decodable {
                        let amount: String?
                        let decimals: Int?
                        let uiAmount: Double?
                        let uiAmountString: String?
                    }
                }
            }
        }
    }
}

// Helper for encoding Any
private struct AnyCodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let dict = value as? [String: Any] {
            var dictContainer = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, val) in dict {
                let codingKey = DynamicCodingKey(stringValue: key)
                if let string = val as? String {
                    try dictContainer.encode(string, forKey: codingKey)
                } else if let int = val as? Int {
                    try dictContainer.encode(int, forKey: codingKey)
                } else if let bool = val as? Bool {
                    try dictContainer.encode(bool, forKey: codingKey)
                } else if let nested = val as? [String: Any] {
                    try dictContainer.encode(AnyCodable(nested), forKey: codingKey)
                }
            }
        } else if let string = value as? String {
            try container.encode(string)
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

// MARK: - Public Models

/// Information about a SPL token account
struct TokenAccountInfo {
    let mint: String
    let amount: UInt64
    let decimals: Int
}

// MARK: - Errors

enum HeliusError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Helius API key not configured"
        case .invalidURL:
            return "Invalid Helius RPC URL"
        case .invalidResponse:
            return "Invalid response from Helius"
        case .httpError(let statusCode):
            return "Helius API error: HTTP \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode Helius response: \(error.localizedDescription)"
        }
    }
}
