import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";
import axios from "axios";
import { SignJWT } from "jose";
import * as crypto from "crypto";

// Coinbase secrets
export const COINBASE_API_KEY = defineSecret("COINBASE_API_KEY");
export const COINBASE_API_KEY_NAME = defineSecret("COINBASE_API_KEY_NAME");
export const COINBASE_API_KEY_PRIVATE_KEY = defineSecret("COINBASE_API_KEY_PRIVATE_KEY");
export const COINBASE_PROJECT_ID = defineSecret("COINBASE_PROJECT_ID");
export const COINBASE_WEBHOOK_SECRET = defineSecret("COINBASE_WEBHOOK_SECRET");

// Coinbase configuration
export const COINBASE_CONFIG = {
  // Base URLs - Updated for Coinbase Pay SDK
  ONRAMP_BASE_URL: "https://pay.coinbase.com/buy",
  OFFRAMP_BASE_URL: "https://pay.coinbase.com/sell",
  PAY_BASE_URL: "https://pay.coinbase.com",

  // Supported assets
  SUPPORTED_ASSETS: {
    USDC: {
      symbol: "USDC",
      network: "solana",
      decimals: 6,
    },
    SOL: {
      symbol: "SOL",
      network: "solana",
      decimals: 9,
    },
  },

  // Default configuration
  DEFAULT_COUNTRY: "US",
  DEFAULT_CURRENCY: "USD",

  // Redirect URLs (these will be called after user completes flow)
  ONRAMP_REDIRECT_URL: "wickett://coinbase-onramp-complete",
  OFFRAMP_REDIRECT_URL: "wickett://coinbase-offramp-complete",

  // Session expiration
  SESSION_EXPIRATION_HOURS: 24,
};

/**
 * Coinbase Onramp Session Request
 */
export interface CreateOnrampSessionRequest {
  destinationWalletAddress: string;
  assetSymbol: string; // e.g., "USDC"
  network: string; // e.g., "solana"
  fiatAmount?: number; // Preset amount
  fiatCurrency?: string; // e.g., "USD"
  country?: string; // e.g., "US"
  redirectUrl?: string;
}

/**
 * Coinbase Onramp Session Response
 */
export interface OnrampSessionResponse {
  sessionId: string;
  checkoutUrl: string;
  status: "created" | "pending" | "completed" | "failed";
  createdAt: string;
}

/**
 * Coinbase Offramp Session Request
 */
export interface CreateOfframpSessionRequest {
  sourceWalletAddress: string;
  assetSymbol: string; // e.g., "USDC"
  network: string; // e.g., "solana"
  fiatAmount?: number;
  fiatCurrency?: string; // e.g., "USD"
  country?: string;
  redirectUrl?: string;
}

/**
 * Coinbase Offramp Session Response
 */
export interface OfframpSessionResponse {
  sessionId: string;
  checkoutUrl: string;
  depositAddress: string; // Where user should send crypto
  status: "created" | "awaiting_crypto" | "processing" | "completed" | "failed";
  createdAt: string;
}

/**
 * Coinbase Webhook Event Types
 */
export enum CoinbaseWebhookEventType {
  ONRAMP_SESSION_CREATED = "onramp.session.created",
  ONRAMP_SESSION_PENDING = "onramp.session.pending",
  ONRAMP_SESSION_COMPLETED = "onramp.session.completed",
  ONRAMP_SESSION_FAILED = "onramp.session.failed",
  OFFRAMP_SESSION_CREATED = "offramp.session.created",
  OFFRAMP_SESSION_AWAITING_CRYPTO = "offramp.session.awaiting_crypto",
  OFFRAMP_SESSION_COMPLETED = "offramp.session.completed",
  OFFRAMP_SESSION_FAILED = "offramp.session.failed",
}

/**
 * Coinbase Webhook Payload
 */
export interface CoinbaseWebhookPayload {
  eventType: CoinbaseWebhookEventType;
  sessionId: string;
  userId?: string;
  status: string;
  destinationWalletAddress?: string;
  fiatAmount?: number;
  cryptoAmount?: number;
  assetSymbol?: string;
  network?: string;
  transactionHash?: string;
  timestamp: string;
}

/**
 * Apple Pay Onramp Order Request
 */
export interface CreateApplePayOrderRequest {
  destinationAddress: string;
  destinationNetwork: string;
  email: string;
  phoneNumber: string;
  phoneNumberVerifiedAt: string;
  paymentAmount?: string;
  paymentCurrency?: string;
  purchaseAmount?: string;
  purchaseCurrency?: string;
  partnerUserRef: string;
  partnerOrderRef?: string;
  agreementAcceptedAt?: string;
  isQuote?: boolean;
}

/**
 * Apple Pay Onramp Order Response
 */
export interface ApplePayOrderResponse {
  order: {
    orderId: string;
    paymentTotal: string;
    paymentSubtotal: string;
    paymentCurrency: string;
    paymentMethod: string;
    purchaseAmount: string;
    purchaseCurrency: string;
    fees: Array<{
      type: string;
      amount: string;
      currency: string;
    }>;
    exchangeRate: string;
    destinationAddress: string;
    destinationNetwork: string;
    status: string;
    txHash?: string;
    createdAt: string;
    updatedAt: string;
  };
  paymentLink: {
    url: string;
    paymentLinkType: string;
  };
}

/**
 * CoinbaseClient - Wrapper around Coinbase Developer Platform API
 */
export class CoinbaseClient {
  private apiKey: string;
  private apiKeyName: string;
  private apiKeyPrivateKey: string;
  private projectId: string;

  // JWT cache to avoid regenerating tokens for every request
  // Tokens expire at 120s, we cache for 90s to be safe
  private jwtCache: Map<string, { token: string; expiresAt: number }> = new Map();
  private static readonly JWT_CACHE_TTL_MS = 90_000; // 90 seconds

  constructor(
    apiKey: string,
    apiKeyName: string,
    apiKeyPrivateKey: string,
    projectId: string
  ) {
    this.apiKey = apiKey;
    this.apiKeyName = apiKeyName;
    this.apiKeyPrivateKey = apiKeyPrivateKey;
    this.projectId = projectId;
  }

  /**
   * Get a JWT token, using cache if available
   */
  private async getJWT(method: string, host: string, path: string): Promise<string> {
    const cacheKey = `${method}:${host}:${path}`;
    const cached = this.jwtCache.get(cacheKey);

    if (cached && Date.now() < cached.expiresAt) {
      return cached.token;
    }

    // Generate new token
    const token = await this.generateJWT(method, host, path);

    // Cache it
    this.jwtCache.set(cacheKey, {
      token,
      expiresAt: Date.now() + CoinbaseClient.JWT_CACHE_TTL_MS,
    });

    return token;
  }

  /**
   * Generate a JWT token for CDP API authentication
   * Uses EdDSA (Ed25519) signing per official CDP documentation
   * JWT tokens expire after 2 minutes
   *
   * Required JWT claims per CDP docs:
   * - sub: API Key Name
   * - iss: "cdp"
   * - nbf: Current timestamp
   * - exp: Current time + 120 seconds
   * - aud: ["cdp_service"]
   * - uri: "METHOD HOST/PATH"
   *
   * Required Headers:
   * - alg: "EdDSA"
   * - kid: API Key Name
   * - typ: "JWT"
   * - nonce: Random 16-char hex string
   *
   * Reference: https://docs.cdp.coinbase.com/api-reference/v2/authentication
   */
  private async generateJWT(method: string, host: string, path: string): Promise<string> {
    try {
      // Decode base64 private key (64 bytes: 32-byte seed + 32-byte public key)
      const privateKeyBytes = Buffer.from(this.apiKeyPrivateKey, "base64");

      // Extract the 32-byte seed (first half)
      const seed = privateKeyBytes.subarray(0, 32);

      // Create Ed25519 key pair from seed
      const privateKey = crypto.createPrivateKey({
        key: Buffer.concat([
          Buffer.from([0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20]),
          seed,
        ]),
        format: "der",
        type: "pkcs8",
      });

      // Generate nonce (16 random hex characters)
      const nonce = crypto.randomBytes(8).toString("hex");

      // Build URI claim (format: "METHOD HOST/PATH")
      const uri = `${method} ${host}/${path.replace(/^\//, "")}`;

      // Get current timestamp
      const now = Math.floor(Date.now() / 1000);

      // Generate JWT with CDP-required claims
      const jwt = await new SignJWT({
        aud: ["cdp_service"],
        uri: uri,
      })
        .setProtectedHeader({
          alg: "EdDSA",
          kid: this.apiKeyName,
          typ: "JWT",
          nonce: nonce,
        })
        .setSubject(this.apiKeyName)
        .setIssuer("cdp")
        .setNotBefore(now)
        .setExpirationTime(now + 120) // 2 minutes
        .sign(privateKey);

      logger.info("✅ JWT token generated successfully", {
        uri,
        nonce: nonce.substring(0, 4) + "...",
      });
      return jwt;
    } catch (error) {
      logger.error("❌ Failed to generate JWT token", {
        error: error instanceof Error ? error.message : String(error),
        errorStack: error instanceof Error ? error.stack : undefined,
        keyNameLength: this.apiKeyName?.length,
        privateKeyLength: this.apiKeyPrivateKey?.length,
        privateKeyPreview: this.apiKeyPrivateKey?.substring(0, 20) + "...",
      });
      throw error;
    }
  }

  /**
   * Generate a session token for secure onramp/offramp initialization
   * Uses JWT authentication with CDP API
   * Session tokens expire after 5 minutes and can only be used once
   */
  private async generateSessionToken(
    walletAddress: string,
    network: string,
    assets: string[],
    clientIp?: string
  ): Promise<string> {
    try {
      const requestHost = "api.developer.coinbase.com";
      const requestPath = "/onramp/v1/token";

      // Prepare request body
      const requestBody = {
        addresses: [
          {
            address: walletAddress,
            blockchains: [network],
          },
        ],
        assets,
        // Use provided client IP or empty string (not recommended for production)
        ...(clientIp && { clientIp }),
      };

      logger.info("Generating session token with JWT auth", {
        walletAddress,
        network,
        assets,
      });

      // Get JWT for authentication (uses cache for performance)
      const jwt = await this.getJWT("POST", requestHost, requestPath);

      // Make API request using JWT Bearer authentication
      const response = await axios.post<{ token: string; channel_id?: string }>(
        `https://${requestHost}${requestPath}`,
        requestBody,
        {
          headers: {
            "Authorization": `Bearer ${jwt}`,
            "Content-Type": "application/json",
          },
        }
      );

      if (!response.data.token) {
        throw new Error("No token in response");
      }

      logger.info("✅ Session token generated successfully");
      return response.data.token;
    } catch (error) {
      logger.error("❌ Failed to generate session token", error);
      if (error instanceof Error && "response" in error) {
        const axiosError = error as { response?: { status: number; data: unknown } };
        if (axiosError.response) {
          logger.error("API error response", {
            status: axiosError.response.status,
            data: axiosError.response.data,
          });
        }
      }
      throw new Error("Session token generation failed");
    }
  }

  /**
   * Create an onramp session
   * Uses Coinbase Pay SDK with secure session token authentication
   */
  async createOnrampSession(
    request: CreateOnrampSessionRequest
  ): Promise<OnrampSessionResponse> {
    try {
      logger.info("Creating Coinbase onramp session", {
        destinationWallet: request.destinationWalletAddress,
        asset: request.assetSymbol,
        network: request.network,
        fiatAmount: request.fiatAmount,
      });

      // Generate a unique session ID for tracking
      const sessionId = `onramp_${Date.now()}_${Math.random().toString(36).substring(7)}`;

      // Generate secure session token
      const sessionToken = await this.generateSessionToken(
        request.destinationWalletAddress,
        request.network,
        [request.assetSymbol || "USDC"]
      );

      // Build Coinbase Pay checkout URL with session token
      const params = new URLSearchParams({
        appId: this.projectId,
        sessionToken,
      });

      // Add optional parameters
      if (request.fiatAmount) {
        params.append("defaultExperience", "buy");
        params.append("presetFiatAmount", request.fiatAmount.toString());
      }

      // Add default network
      if (request.network) {
        params.append("defaultNetwork", request.network);
      }

      const checkoutUrl = `${COINBASE_CONFIG.ONRAMP_BASE_URL}/select-asset?${params.toString()}`;

      logger.info("✅ Coinbase onramp session created", {
        sessionId,
        checkoutUrl: checkoutUrl.substring(0, 100) + "...",
      });

      return {
        sessionId,
        checkoutUrl,
        status: "created",
        createdAt: new Date().toISOString(),
      };
    } catch (error) {
      logger.error("❌ Failed to create Coinbase onramp session", error);
      throw error;
    }
  }

  /**
   * Create an Apple Pay onramp order (Headless)
   * Uses Coinbase Onramp API for native Apple Pay integration
   * Returns payment link to embed in WKWebView
   *
   * @param request - Apple Pay order details
   * @returns Order details with Apple Pay payment link
   */
  async createApplePayOnrampOrder(
    request: CreateApplePayOrderRequest
  ): Promise<ApplePayOrderResponse> {
    try {
      logger.info("Creating Apple Pay onramp order", {
        destinationAddress: request.destinationAddress,
        destinationNetwork: request.destinationNetwork,
        paymentAmount: request.paymentAmount,
        purchaseCurrency: request.purchaseCurrency,
      });

      const requestHost = "api.cdp.coinbase.com";
      const requestPath = "/platform/v2/onramp/orders";

      // Get JWT for authentication (uses cache for performance)
      const jwt = await this.getJWT("POST", requestHost, requestPath);

      // Prepare request body
      const requestBody = {
        destinationAddress: request.destinationAddress,
        destinationNetwork: request.destinationNetwork,
        email: request.email,
        phoneNumber: request.phoneNumber,
        phoneNumberVerifiedAt: request.phoneNumberVerifiedAt,
        paymentMethod: "GUEST_CHECKOUT_APPLE_PAY",
        partnerUserRef: request.partnerUserRef,
        // Always include purchaseCurrency (required by Coinbase)
        purchaseCurrency: request.purchaseCurrency || "USDC",
        // Always include agreementAcceptedAt (required by Coinbase)
        agreementAcceptedAt: request.agreementAcceptedAt || new Date().toISOString(),
        ...(request.paymentAmount && {
          paymentAmount: request.paymentAmount,
          paymentCurrency: request.paymentCurrency || "USD",
        }),
        ...(request.purchaseAmount && {
          purchaseAmount: request.purchaseAmount,
        }),
        ...(request.partnerOrderRef && { partnerOrderRef: request.partnerOrderRef }),
        isQuote: request.isQuote || false,
      };

      // Make API request using JWT Bearer authentication
      const response = await axios.post<ApplePayOrderResponse>(
        `https://${requestHost}${requestPath}`,
        requestBody,
        {
          headers: {
            "Authorization": `Bearer ${jwt}`,
            "Content-Type": "application/json",
          },
        }
      );

      logger.info("✅ Apple Pay onramp order created successfully", {
        orderId: response.data.order.orderId,
        paymentTotal: response.data.order.paymentTotal,
        purchaseAmount: response.data.order.purchaseAmount,
      });

      return response.data;
    } catch (error) {
      logger.error("❌ Failed to create Apple Pay onramp order", error);
      throw error;
    }
  }

  /**
   * Create an offramp session
   * Uses Coinbase Pay SDK - generates checkout URL for selling crypto
   */
  async createOfframpSession(
    request: CreateOfframpSessionRequest
  ): Promise<OfframpSessionResponse> {
    try {
      logger.info("Creating Coinbase offramp session", {
        sourceWallet: request.sourceWalletAddress,
        asset: request.assetSymbol,
        network: request.network,
        fiatAmount: request.fiatAmount,
      });

      // Generate a unique session ID
      const sessionId = `offramp_${Date.now()}_${Math.random().toString(36).substring(7)}`;

      // For offramp, we generate a Coinbase wallet address as deposit address
      // In practice, Coinbase provides this through their UI flow
      // This is a placeholder - user will get actual address in Coinbase checkout
      const depositAddress = `coinbase_deposit_${sessionId}`;

      // Build Coinbase Pay sell URL with query parameters
      const params = new URLSearchParams({
        appId: this.projectId,
        defaultExperience: "send",
      });

      // Add asset and network
      if (request.assetSymbol) {
        params.append("assets", `["${request.assetSymbol}"]`);
      }
      if (request.network) {
        params.append("blockchains", `["${request.network}"]`);
      }

      const checkoutUrl = `${COINBASE_CONFIG.OFFRAMP_BASE_URL}?${params.toString()}`;

      logger.info("✅ Coinbase offramp session created", {
        sessionId,
        depositAddress,
      });

      return {
        sessionId,
        checkoutUrl,
        depositAddress,
        status: "created",
        createdAt: new Date().toISOString(),
      };
    } catch (error) {
      logger.error("❌ Failed to create Coinbase offramp session", error);
      throw error;
    }
  }

  /**
   * Get session status
   * Note: Coinbase Pay doesn't provide a direct status API
   * Status updates come through webhooks instead
   * This method is kept for compatibility but relies on Firestore data
   */
  async getSessionStatus(sessionId: string): Promise<{
    status: string;
    transactionHash?: string;
    cryptoAmount?: number;
    fiatAmount?: number;
  }> {
    try {
      logger.info("Session status check - relying on webhook updates", { sessionId });

      // Coinbase Pay doesn't expose a status API
      // Status is updated via webhooks and stored in Firestore
      // This is handled by the get-transfer-status Cloud Function
      return {
        status: "pending",
      };
    } catch (error) {
      logger.error("❌ Failed to get Coinbase session status", error);
      throw error;
    }
  }

  /**
   * Verify webhook signature
   * TODO: Implement signature verification based on Coinbase docs
   */
  verifyWebhookSignature(
    payload: string,
    signature: string,
    webhookSecret: string
  ): boolean {
    try {
      // TODO: Implement actual signature verification
      // This will likely use HMAC-SHA256 or similar
      // Example (pseudocode):
      // const computedSignature = crypto.createHmac('sha256', webhookSecret)
      //   .update(payload)
      //   .digest('hex');
      // return computedSignature === signature;

      logger.info("Verifying Coinbase webhook signature");

      // Placeholder - always return true for now
      // IMPORTANT: Implement actual verification before production!
      return true;
    } catch (error) {
      logger.error("❌ Failed to verify webhook signature", error);
      return false;
    }
  }
}

/**
 * Get singleton CoinbaseClient instance
 */
export function getCoinbaseClient(): CoinbaseClient {
  // Trim all secrets to remove any whitespace/newlines
  const apiKey = COINBASE_API_KEY.value().trim();
  const apiKeyName = COINBASE_API_KEY_NAME.value().trim();
  const apiKeyPrivateKey = COINBASE_API_KEY_PRIVATE_KEY.value().trim();
  const projectId = COINBASE_PROJECT_ID.value().trim();
  return new CoinbaseClient(apiKey, apiKeyName, apiKeyPrivateKey, projectId);
}
