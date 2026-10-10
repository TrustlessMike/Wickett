import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  getCoinbaseClient,
  COINBASE_API_KEY,
  COINBASE_API_KEY_NAME,
  COINBASE_API_KEY_PRIVATE_KEY,
  COINBASE_PROJECT_ID,
  COINBASE_WEBHOOK_SECRET,
  COINBASE_CONFIG,
} from "./coinbase-client";
import { isValidSolanaAddress } from "../utils/solana-utils";
import { getPrivyClient, PRIVY_APP_ID, PRIVY_APP_SECRET } from "../config/privy-config";

/**
 * Onramp session status enum
 */
export enum OnrampSessionStatus {
  CREATED = "created",
  PENDING = "pending",
  COMPLETED = "completed",
  FAILED = "failed",
  EXPIRED = "expired",
}

/**
 * Firestore Onramp Session Document
 */
export interface OnrampSessionDocument {
  id: string;
  userId: string;
  coinbaseSessionId: string;
  walletAddress: string;
  assetSymbol: string;
  network: string;
  fiatAmount?: number;
  fiatCurrency: string;
  country: string;
  status: OnrampSessionStatus;
  checkoutUrl: string;
  transactionHash?: string;
  cryptoAmount?: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  completedAt?: Timestamp;
  failureReason?: string;
}

/**
 * Request body for creating onramp session
 */
interface CreateOnrampSessionRequest {
  walletAddress: string;
  fiatAmount?: number;
  assetSymbol?: string; // Default: USDC
  country?: string;
  fiatCurrency?: string;
  privyAccessToken?: string; // Privy access token for additional security
}

/**
 * Response for creating onramp session
 */
interface CreateOnrampSessionResponse {
  sessionId: string;
  coinbaseSessionId: string;
  checkoutUrl: string;
  status: string;
}

/**
 * Firebase Cloud Function: Create Coinbase Onramp Session
 *
 * This function creates a new Coinbase onramp session and returns the checkout URL
 * for the user to complete their purchase.
 *
 * Flow:
 * 1. Validate user authentication and wallet address
 * 2. Create onramp session via Coinbase API
 * 3. Store session in Firestore
 * 4. Return checkout URL to client
 *
 * @param request - Contains walletAddress, fiatAmount, etc.
 * @param context - Firebase auth context
 * @returns Session info with checkout URL
 */
export const createCoinbaseOnrampSession = onCall(
  {
    secrets: [
      COINBASE_API_KEY,
      COINBASE_API_KEY_NAME,
      COINBASE_API_KEY_PRIVATE_KEY,
      COINBASE_PROJECT_ID,
      COINBASE_WEBHOOK_SECRET,
      PRIVY_APP_ID,
      PRIVY_APP_SECRET,
    ],
    enforceAppCheck: false, // TODO: Enable in production
    cors: true,
  },
  async (request) => {
    const db = getFirestore();
    const userId = request.auth?.uid;

    // Validate authentication
    if (!userId) {
      logger.warn("Unauthenticated onramp session creation attempt");
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const data = request.data as CreateOnrampSessionRequest;

    // Verify Privy access token if provided (required for CDP security compliance)
    if (data.privyAccessToken) {
      try {
        const privy = getPrivyClient();
        await privy.utils().auth().verifyAuthToken(data.privyAccessToken);
        logger.info("✅ Privy access token verified for user", { userId });
      } catch (error) {
        logger.warn("❌ Invalid Privy access token", { userId, error });
        throw new HttpsError("unauthenticated", "Invalid Privy access token");
      }
    } else {
      logger.warn("⚠️ No Privy access token provided - consider requiring for production", { userId });
    }

    // Validate required fields
    if (!data.walletAddress) {
      throw new HttpsError("invalid-argument", "Wallet address is required");
    }

    // Validate Solana address
    if (!isValidSolanaAddress(data.walletAddress)) {
      throw new HttpsError("invalid-argument", "Invalid Solana wallet address");
    }

    // Set defaults
    const assetSymbol = data.assetSymbol || "USDC";
    const network = "solana";
    const fiatCurrency = data.fiatCurrency || COINBASE_CONFIG.DEFAULT_CURRENCY;
    const country = data.country || COINBASE_CONFIG.DEFAULT_COUNTRY;

    // Validate asset
    if (!(assetSymbol in COINBASE_CONFIG.SUPPORTED_ASSETS)) {
      throw new HttpsError(
        "invalid-argument",
        `Unsupported asset: ${assetSymbol}. Supported: ${Object.keys(
          COINBASE_CONFIG.SUPPORTED_ASSETS
        ).join(", ")}`
      );
    }

    logger.info("Creating Coinbase onramp session", {
      userId,
      walletAddress: data.walletAddress,
      assetSymbol,
      fiatAmount: data.fiatAmount,
      fiatCurrency,
    });

    try {
      // Create Coinbase onramp session
      const coinbaseClient = getCoinbaseClient();
      const coinbaseSession = await coinbaseClient.createOnrampSession({
        destinationWalletAddress: data.walletAddress,
        assetSymbol,
        network,
        fiatAmount: data.fiatAmount,
        fiatCurrency,
        country,
        redirectUrl: COINBASE_CONFIG.ONRAMP_REDIRECT_URL,
      });

      // Create session document in Firestore
      const sessionRef = db.collection("coinbaseOnrampSessions").doc();
      const sessionId = sessionRef.id;

      const sessionDoc: OnrampSessionDocument = {
        id: sessionId,
        userId,
        coinbaseSessionId: coinbaseSession.sessionId,
        walletAddress: data.walletAddress,
        assetSymbol,
        network,
        fiatAmount: data.fiatAmount,
        fiatCurrency,
        country,
        status: OnrampSessionStatus.CREATED,
        checkoutUrl: coinbaseSession.checkoutUrl,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      };

      await sessionRef.set(sessionDoc);

      // Update user's last onramp timestamp
      await db
        .collection("users")
        .doc(userId)
        .update({
          lastOnrampAt: FieldValue.serverTimestamp(),
        });

      logger.info("✅ Coinbase onramp session created successfully", {
        sessionId,
        coinbaseSessionId: coinbaseSession.sessionId,
        userId,
      });

      const response: CreateOnrampSessionResponse = {
        sessionId,
        coinbaseSessionId: coinbaseSession.sessionId,
        checkoutUrl: coinbaseSession.checkoutUrl,
        status: coinbaseSession.status,
      };

      return response;
    } catch (error: any) {
      logger.error("❌ Failed to create Coinbase onramp session", {
        userId,
        error: error.message,
        stack: error.stack,
      });

      // Categorize errors
      if (error.message?.includes("API error")) {
        throw new HttpsError(
          "unavailable",
          "Coinbase service temporarily unavailable. Please try again later."
        );
      }

      throw new HttpsError("internal", "Failed to create onramp session");
    }
  }
);
