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
import { getSolanaConnection } from "../config/solana-config";
import { PublicKey } from "@solana/web3.js";
import { getPrivyClient, PRIVY_APP_ID, PRIVY_APP_SECRET } from "../config/privy-config";

/**
 * Offramp session status enum
 */
export enum OfframpSessionStatus {
  CREATED = "created",
  AWAITING_CRYPTO = "awaiting_crypto",
  PROCESSING = "processing",
  COMPLETED = "completed",
  FAILED = "failed",
  EXPIRED = "expired",
}

/**
 * Firestore Offramp Session Document
 */
export interface OfframpSessionDocument {
  id: string;
  userId: string;
  coinbaseSessionId: string;
  walletAddress: string;
  depositAddress: string; // Coinbase address where user sends crypto
  assetSymbol: string;
  network: string;
  fiatAmount?: number;
  fiatCurrency: string;
  country: string;
  cryptoAmount?: number;
  status: OfframpSessionStatus;
  checkoutUrl: string;
  transactionHash?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  completedAt?: Timestamp;
  failureReason?: string;
}

/**
 * Request body for creating offramp session
 */
interface CreateOfframpSessionRequest {
  walletAddress: string;
  fiatAmount?: number;
  assetSymbol?: string; // Default: USDC
  country?: string;
  fiatCurrency?: string;
  privyAccessToken?: string; // Privy access token for additional security
}

/**
 * Response for creating offramp session
 */
interface CreateOfframpSessionResponse {
  sessionId: string;
  coinbaseSessionId: string;
  checkoutUrl: string;
  depositAddress: string;
  status: string;
}

/**
 * Firebase Cloud Function: Create Coinbase Offramp Session
 *
 * This function creates a new Coinbase offramp session and returns:
 * 1. Checkout URL for user to set up bank details
 * 2. Deposit address where user should send crypto
 *
 * Flow:
 * 1. Validate user authentication and wallet address
 * 2. Check user has sufficient balance (optional)
 * 3. Create offramp session via Coinbase API
 * 4. Store session in Firestore
 * 5. Return checkout URL and deposit address to client
 * 6. Client will prompt user to send crypto to deposit address
 *
 * @param request - Contains walletAddress, fiatAmount, etc.
 * @param context - Firebase auth context
 * @returns Session info with checkout URL and deposit address
 */
export const createCoinbaseOfframpSession = onCall(
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
      logger.warn("Unauthenticated offramp session creation attempt");
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const data = request.data as CreateOfframpSessionRequest;

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

    if (!data.fiatAmount || data.fiatAmount <= 0) {
      throw new HttpsError(
        "invalid-argument",
        "Valid fiat amount is required for offramp"
      );
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

    logger.info("Creating Coinbase offramp session", {
      userId,
      walletAddress: data.walletAddress,
      assetSymbol,
      fiatAmount: data.fiatAmount,
      fiatCurrency,
    });

    try {
      // Optional: Check user has sufficient balance
      // This is a courtesy check - the actual transaction will validate balance
      if (assetSymbol === "USDC") {
        try {
          const connection = getSolanaConnection();
          const walletPubkey = new PublicKey(data.walletAddress);

          // Get USDC token accounts (mint: EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v)
          const USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
          const tokenAccounts = await connection.getParsedTokenAccountsByOwner(
            walletPubkey,
            { mint: new PublicKey(USDC_MINT) }
          );

          let totalUsdcBalance = 0;
          tokenAccounts.value.forEach((accountInfo) => {
            const parsedInfo = accountInfo.account.data.parsed.info;
            totalUsdcBalance += parsedInfo.tokenAmount.uiAmount || 0;
          });

          logger.info("User USDC balance check", {
            userId,
            balance: totalUsdcBalance,
            requestedAmount: data.fiatAmount,
          });

          // Note: fiatAmount is in USD, not USDC, so this is approximate
          // In production, you'd want to convert fiatAmount to USDC using current exchange rate
          if (totalUsdcBalance < data.fiatAmount * 0.95) {
            // 5% buffer for fees
            logger.warn("User may have insufficient USDC balance", {
              userId,
              balance: totalUsdcBalance,
              requestedFiatAmount: data.fiatAmount,
            });
            // Don't throw error - let user proceed and handle in UI
          }
        } catch (balanceError) {
          logger.warn("Could not check user balance", {
            userId,
            error: balanceError,
          });
          // Continue anyway - balance check is optional
        }
      }

      // Create Coinbase offramp session
      const coinbaseClient = getCoinbaseClient();
      const coinbaseSession = await coinbaseClient.createOfframpSession({
        sourceWalletAddress: data.walletAddress,
        assetSymbol,
        network,
        fiatAmount: data.fiatAmount,
        fiatCurrency,
        country,
        redirectUrl: COINBASE_CONFIG.OFFRAMP_REDIRECT_URL,
      });

      // Create session document in Firestore
      const sessionRef = db.collection("coinbaseOfframpSessions").doc();
      const sessionId = sessionRef.id;

      const sessionDoc: OfframpSessionDocument = {
        id: sessionId,
        userId,
        coinbaseSessionId: coinbaseSession.sessionId,
        walletAddress: data.walletAddress,
        depositAddress: coinbaseSession.depositAddress,
        assetSymbol,
        network,
        fiatAmount: data.fiatAmount,
        fiatCurrency,
        country,
        status: OfframpSessionStatus.CREATED,
        checkoutUrl: coinbaseSession.checkoutUrl,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      };

      await sessionRef.set(sessionDoc);

      // Update user's last offramp timestamp
      await db
        .collection("users")
        .doc(userId)
        .update({
          lastOfframpAt: FieldValue.serverTimestamp(),
        });

      logger.info("✅ Coinbase offramp session created successfully", {
        sessionId,
        coinbaseSessionId: coinbaseSession.sessionId,
        userId,
        depositAddress: coinbaseSession.depositAddress,
      });

      const response: CreateOfframpSessionResponse = {
        sessionId,
        coinbaseSessionId: coinbaseSession.sessionId,
        checkoutUrl: coinbaseSession.checkoutUrl,
        depositAddress: coinbaseSession.depositAddress,
        status: coinbaseSession.status,
      };

      return response;
    } catch (error: any) {
      logger.error("❌ Failed to create Coinbase offramp session", {
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

      if (error.message?.includes("Insufficient")) {
        throw new HttpsError("failed-precondition", "Insufficient balance");
      }

      throw new HttpsError("internal", "Failed to create offramp session");
    }
  }
);
