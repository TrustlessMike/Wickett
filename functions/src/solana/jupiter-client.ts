import axios from "axios";
import { PublicKey, VersionedTransaction } from "@solana/web3.js";
import * as logger from "firebase-functions/logger";
import { retryWithBackoff } from "../utils/solana-utils";
import {defineSecret} from "firebase-functions/params";

// Jupiter API configuration
// Ultra API: https://api.jup.ag/ultra/v1 - Combined quote+swap in /order endpoint
// Standard API: https://quote-api.jup.ag/v6 - Separate /quote + /swap endpoints
const JUPITER_ULTRA_API_BASE_URL = "https://api.jup.ag/ultra/v1";
const JUPITER_STANDARD_API_BASE_URL = "https://quote-api.jup.ag/v6";

// Jupiter Ultra API key secret
export const JUPITER_API_KEY = defineSecret("JUPITER_API_KEY");

export interface JupiterQuoteParams {
  inputMint: string; // Token mint address to swap from
  outputMint: string; // Token mint address to swap to
  amount: number; // Amount in smallest unit (e.g., lamports for SOL)
  slippageBps?: number; // Slippage tolerance in basis points (default: 50 = 0.5%)
  platformFeeBps?: number; // Platform fee in basis points (e.g., 50 = 0.5%)
  onlyDirectRoutes?: boolean; // Only direct routes (default: false)
  asLegacyTransaction?: boolean; // Return legacy transaction instead of versioned
}

export interface JupiterQuoteResponse {
  inputMint: string;
  inAmount: string;
  outputMint: string;
  outAmount: string;
  otherAmountThreshold: string;
  swapMode: string;
  slippageBps: number;
  priceImpactPct: string;
  routePlan: Array<{
    swapInfo: {
      ammKey: string;
      label: string;
      inputMint: string;
      outputMint: string;
      inAmount: string;
      outAmount: string;
      feeAmount: string;
      feeMint: string;
    };
    percent: number;
  }>;
}

export interface JupiterSwapParams {
  quoteResponse: JupiterQuoteResponse;
  userPublicKey: string;
  wrapAndUnwrapSol?: boolean;
  feeAccount?: string;
  dynamicComputeUnitLimit?: boolean;
  prioritizationFeeLamports?: number;
  // Ultra API referral fee params
  referralAccount?: string;
  referralFeeBps?: number; // 50-255 bps for Ultra API
}

export interface JupiterSwapResponse {
  swapTransaction: string; // Base64 encoded transaction
  lastValidBlockHeight: number;
  prioritizationFeeLamports?: number;
}

/**
 * Jupiter API Client for Solana token swaps
 * Uses Ultra API when API key is available, falls back to Standard API otherwise
 */
export class JupiterClient {
  private ultraClient: any;
  private standardClient: any;
  private initialized = false;
  private hasApiKey = false;

  constructor() {
    // Clients will be initialized on first use (secrets only available at runtime)
  }

  private initializeClients() {
    if (this.initialized) return;

    // Get API key from secret if available
    const apiKey = JUPITER_API_KEY.value();
    this.hasApiKey = !!apiKey;

    // Ultra API client (requires API key)
    this.ultraClient = axios.create({
      baseURL: JUPITER_ULTRA_API_BASE_URL,
      timeout: 30000,
      headers: {
        "Content-Type": "application/json",
        ...(apiKey ? {"x-api-key": apiKey} : {}),
      },
    });

    // Standard API client (fallback, no key required)
    this.standardClient = axios.create({
      baseURL: JUPITER_STANDARD_API_BASE_URL,
      timeout: 30000,
      headers: {
        "Content-Type": "application/json",
      },
    });

    if (apiKey) {
      logger.info("✅ Jupiter Ultra API initialized with API key");
    } else {
      logger.warn("⚠️  Jupiter API key not found - using Standard API (limited rates)");
    }

    this.initialized = true;
  }

  /**
   * Get a quote for a token swap using Standard API
   * Note: This is used for quote-only operations (like auto-convert preview)
   * For actual swaps, use getOrder() which uses Ultra API
   */
  async getQuote(params: JupiterQuoteParams): Promise<JupiterQuoteResponse> {
    this.initializeClients();
    return retryWithBackoff(async () => {
      try {
        logger.info(`Fetching Jupiter quote: ${params.inputMint} -> ${params.outputMint}`);

        // Use Standard API for quotes (/quote endpoint)
        const response = await this.standardClient.get("/quote", {
          params: {
            inputMint: params.inputMint,
            outputMint: params.outputMint,
            amount: params.amount,
            slippageBps: params.slippageBps || 50,
            onlyDirectRoutes: params.onlyDirectRoutes || false,
            asLegacyTransaction: params.asLegacyTransaction || false,
          },
        });

        logger.info(
          `Jupiter quote received: ${response.data.inAmount} -> ${response.data.outAmount}`
        );
        logger.info(`Price impact: ${response.data.priceImpactPct}%`);

        return response.data;
      } catch (error) {
        if ((error as any).response) {
          logger.error("Jupiter quote API error:", {
            status: error.response?.status,
            data: error.response?.data,
          });
          throw new Error(
            `Jupiter quote failed: ${error.response?.data?.error || error.message}`
          );
        }
        throw error;
      }
    }, 3);
  }

  /**
   * Get swap transaction from Jupiter Standard API /swap endpoint
   * This takes a quote response and builds a transaction
   */
  async getSwapTransaction(params: JupiterSwapParams): Promise<JupiterSwapResponse> {
    this.initializeClients();
    return retryWithBackoff(async () => {
      try {
        logger.info(`Building Jupiter swap for user: ${params.userPublicKey}`);

        // Build request body for /swap POST endpoint
        const requestBody: Record<string, any> = {
          quoteResponse: params.quoteResponse,
          userPublicKey: params.userPublicKey,
          wrapAndUnwrapSol: params.wrapAndUnwrapSol ?? true,
          dynamicComputeUnitLimit: params.dynamicComputeUnitLimit ?? true,
        };

        // Add fee account if provided
        if (params.feeAccount) {
          requestBody.feeAccount = params.feeAccount;
        }

        // Add prioritization fee if provided
        if (params.prioritizationFeeLamports) {
          requestBody.prioritizationFeeLamports = params.prioritizationFeeLamports;
        }

        // Standard API uses /swap (POST)
        const response = await this.standardClient.post("/swap", requestBody);

        logger.info("✅ Jupiter swap transaction built successfully");

        return {
          swapTransaction: response.data.swapTransaction,
          lastValidBlockHeight: response.data.lastValidBlockHeight || 0,
        };
      } catch (error) {
        if ((error as any).response) {
          logger.error("Jupiter swap API error:", {
            status: error.response?.status,
            data: JSON.stringify(error.response?.data),
          });
          throw new Error(
            `Jupiter swap failed: ${JSON.stringify(error.response?.data) || error.message}`
          );
        }
        throw error;
      }
    }, 3);
  }

  /**
   * Get order from Jupiter Ultra API - combined quote + transaction in one call
   * This is the recommended approach for swaps when API key is available
   */
  async getOrder(params: {
    inputMint: string;
    outputMint: string;
    amount: number;
    taker: string;  // User's wallet address
    slippageBps?: number;
    referralAccount?: string;
    referralFeeBps?: number;
  }): Promise<{
    transaction: string;
    requestId: string;
    inAmount: string;
    outAmount: string;
    inputMint: string;
    outputMint: string;
  }> {
    this.initializeClients();

    if (!this.hasApiKey) {
      throw new Error("Ultra API requires an API key. Use getQuote + getSwapTransaction instead.");
    }

    return retryWithBackoff(async () => {
      try {
        logger.info(`Fetching Jupiter Ultra order: ${params.inputMint} -> ${params.outputMint}`);
        logger.info(`Amount: ${params.amount}, Taker: ${params.taker}`);

        // Ultra API uses GET /order with all params as query params
        const queryParams: Record<string, any> = {
          inputMint: params.inputMint,
          outputMint: params.outputMint,
          amount: params.amount,
          taker: params.taker,
        };

        if (params.slippageBps) {
          queryParams.slippageBps = params.slippageBps;
        }
        if (params.referralAccount) {
          queryParams.referralAccount = params.referralAccount;
        }
        if (params.referralFeeBps) {
          queryParams.referralFee = params.referralFeeBps;
        }

        const response = await this.ultraClient.get("/order", { params: queryParams });

        logger.info(`✅ Jupiter Ultra order received: ${response.data.inAmount} -> ${response.data.outAmount}`);

        return {
          transaction: response.data.transaction,
          requestId: response.data.requestId,
          inAmount: response.data.inAmount,
          outAmount: response.data.outAmount,
          inputMint: response.data.inputMint,
          outputMint: response.data.outputMint,
        };
      } catch (error) {
        if ((error as any).response) {
          logger.error("Jupiter Ultra order API error:", {
            status: error.response?.status,
            data: JSON.stringify(error.response?.data),
          });
          throw new Error(
            `Jupiter order failed: ${JSON.stringify(error.response?.data) || error.message}`
          );
        }
        throw error;
      }
    }, 3);
  }

  /**
   * Get quote and swap transaction in one call
   */
  async getQuoteAndSwap(
    params: JupiterQuoteParams & { userPublicKey: string; feeAccount?: string }
  ): Promise<{ quote: JupiterQuoteResponse; swap: JupiterSwapResponse }> {
    try {
      // Get quote
      const quote = await this.getQuote(params);

      // Get swap transaction
      const swap = await this.getSwapTransaction({
        quoteResponse: quote,
        userPublicKey: params.userPublicKey,
        feeAccount: params.feeAccount,
      });

      return { quote, swap };
    } catch (error) {
      logger.error("Jupiter quote and swap failed:", error);
      throw error;
    }
  }

  /**
   * Deserialize swap transaction from base64
   */
  deserializeSwapTransaction(swapTransactionBase64: string): VersionedTransaction {
    try {
      const buffer = Buffer.from(swapTransactionBase64, "base64");
      const transaction = VersionedTransaction.deserialize(buffer);
      logger.info("✅ Swap transaction deserialized successfully");
      return transaction;
    } catch (error) {
      logger.error("Failed to deserialize swap transaction:", error);
      throw new Error("Failed to deserialize swap transaction");
    }
  }

  /**
   * Get token price from Jupiter
   */
  async getTokenPrice(tokenMint: string): Promise<{ price: number; timestamp: number }> {
    this.initializeClients();
    try {
      const response = await axios.get(`https://price.jup.ag/v4/price`, {
        params: { ids: tokenMint },
      });

      const priceData = (response as any).data.data[tokenMint];
      if (!priceData) {
        throw new Error(`Price not found for token: ${tokenMint}`);
      }

      return {
        price: priceData.price,
        timestamp: Date.now(),
      };
    } catch (error) {
      logger.error("Failed to get token price:", error);
      throw error;
    }
  }

  /**
   * Calculate expected output amount with slippage
   */
  calculateMinimumOutput(
    outputAmount: string,
    slippageBps: number = 50
  ): { minimum: string; slippagePercent: number } {
    const amount = BigInt(outputAmount);
    const slippageFactor = BigInt(10000 - slippageBps);
    const minimum = (amount * slippageFactor) / BigInt(10000);

    return {
      minimum: minimum.toString(),
      slippagePercent: slippageBps / 100,
    };
  }

  /**
   * Validate token addresses
   */
  validateTokenMints(inputMint: string, outputMint: string): void {
    try {
      new PublicKey(inputMint);
      new PublicKey(outputMint);

      if (inputMint === outputMint) {
        throw new Error("Input and output mints cannot be the same");
      }
    } catch (error) {
      throw new Error(
        `Invalid token mint address: ${error instanceof Error ? error.message : "Unknown error"}`
      );
    }
  }
}

// Common token mints for convenience
export const COMMON_TOKEN_MINTS = {
  SOL: "So11111111111111111111111111111111111111112",
  USDC: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
  USDT: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",
  BONK: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
  WIF: "EKpQGSJtjMFqKZ9KQanSqYXRcF8fBopzLHYxdM65zcjm",
};

/**
 * Helper function to get readable token name
 */
export function getTokenName(mint: string): string {
  const tokenEntry = Object.entries(COMMON_TOKEN_MINTS).find(
    ([_, address]) => address === mint
  );
  return tokenEntry ? tokenEntry[0] : mint.substring(0, 8);
}

// Export singleton instance
export const jupiterClient = new JupiterClient();
