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
} from "./coinbase-client";
import { isValidSolanaAddress } from "../utils/solana-utils";
import { getPrivyClient, PRIVY_APP_ID, PRIVY_APP_SECRET } from "../config/privy-config";

/**
 * Request body for creating Apple Pay onramp order
 */
interface CreateApplePayOrderRequest {
  walletAddress: string;
  email: string;
  phoneNumber: string;
  phoneNumberVerifiedAt?: string;
  paymentAmount?: number;
  paymentCurrency?: string;
  purchaseAmount?: number;
  purchaseCurrency?: string;
  privyAccessToken?: string; // Privy access token for additional security
}

/**
 * Response for creating Apple Pay onramp order
 */
interface CreateApplePayOrderResponse {
  orderId: string;
  sessionId: string;
  paymentLinkUrl: string;
  paymentTotal: string;
  paymentCurrency: string;
  purchaseAmount: string;
  purchaseCurrency: string;
  status: string;
}

/**
 * Firebase Cloud Function: Create Coinbase Apple Pay Onramp Order
 *
 * This function creates a headless Apple Pay onramp order using Coinbase Platform v2 API.
 * The flow is completely native - no web views required.
 *
 * Flow:
 * 1. Validate user authentication and wallet address
 * 2. Create Apple Pay order via Coinbase Platform API
 * 3. Store order in Firestore
 * 4. Return payment link for native Apple Pay sheet
 *
 * @param request - Contains walletAddress, email, phoneNumber, amounts, etc.
 * @param context - Firebase auth context
 * @returns Order info with native payment link
 */
export const createCoinbaseApplePayOrder = onCall(
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
      logger.warn("Unauthenticated Apple Pay order creation attempt");
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const data = request.data as CreateApplePayOrderRequest;

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

    if (!data.email) {
      throw new HttpsError("invalid-argument", "Email is required");
    }

    if (!data.phoneNumber) {
      throw new HttpsError("invalid-argument", "Phone number is required");
    }

    // Validate Solana address
    if (!isValidSolanaAddress(data.walletAddress)) {
      throw new HttpsError("invalid-argument", "Invalid Solana wallet address");
    }

    // Set defaults
    const purchaseCurrency = data.purchaseCurrency || "USDC";
    const paymentCurrency = data.paymentCurrency || "USD";
    const phoneNumberVerifiedAt = data.phoneNumberVerifiedAt || new Date().toISOString();

    logger.info("Creating Coinbase Apple Pay order", {
      userId,
      walletAddress: data.walletAddress,
      purchaseCurrency,
      paymentAmount: data.paymentAmount,
      purchaseAmount: data.purchaseAmount,
    });

    try {
      // Create Coinbase Apple Pay order
      const coinbaseClient = getCoinbaseClient();
      const coinbaseOrder = await coinbaseClient.createApplePayOnrampOrder({
        destinationAddress: data.walletAddress,
        destinationNetwork: "solana",
        email: data.email,
        phoneNumber: data.phoneNumber,
        phoneNumberVerifiedAt,
        paymentAmount: data.paymentAmount?.toString(),
        paymentCurrency,
        purchaseAmount: data.purchaseAmount?.toString(),
        purchaseCurrency,
        partnerUserRef: userId,
        isQuote: false,
      });

      // Create order document in Firestore
      const orderRef = db.collection("coinbaseApplePayOrders").doc();
      const sessionId = orderRef.id;

      const orderDoc = {
        id: sessionId,
        userId,
        coinbaseOrderId: coinbaseOrder.order.orderId,
        walletAddress: data.walletAddress,
        purchaseCurrency: coinbaseOrder.order.purchaseCurrency,
        paymentCurrency: coinbaseOrder.order.paymentCurrency,
        paymentTotal: coinbaseOrder.order.paymentTotal,
        paymentSubtotal: coinbaseOrder.order.paymentSubtotal,
        purchaseAmount: coinbaseOrder.order.purchaseAmount,
        exchangeRate: coinbaseOrder.order.exchangeRate,
        fees: coinbaseOrder.order.fees,
        status: coinbaseOrder.order.status,
        paymentLinkUrl: coinbaseOrder.paymentLink.url,
        paymentLinkType: coinbaseOrder.paymentLink.paymentLinkType,
        transactionHash: coinbaseOrder.order.txHash,
        createdAt: Timestamp.now(),
        updatedAt: Timestamp.now(),
      };

      await orderRef.set(orderDoc);

      // Update user's last onramp timestamp
      await db
        .collection("users")
        .doc(userId)
        .update({
          lastOnrampAt: FieldValue.serverTimestamp(),
        });

      logger.info("✅ Coinbase Apple Pay order created successfully", {
        sessionId,
        coinbaseOrderId: coinbaseOrder.order.orderId,
        userId,
        paymentLinkUrl: coinbaseOrder.paymentLink.url,
      });

      const response: CreateApplePayOrderResponse = {
        orderId: coinbaseOrder.order.orderId,
        sessionId,
        paymentLinkUrl: coinbaseOrder.paymentLink.url,
        paymentTotal: coinbaseOrder.order.paymentTotal,
        paymentCurrency: coinbaseOrder.order.paymentCurrency,
        purchaseAmount: coinbaseOrder.order.purchaseAmount,
        purchaseCurrency: coinbaseOrder.order.purchaseCurrency,
        status: coinbaseOrder.order.status,
      };

      return response;
    } catch (error: any) {
      logger.error("❌ Failed to create Coinbase Apple Pay order", {
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

      if (error.message?.includes("Invalid destination")) {
        throw new HttpsError("invalid-argument", "Invalid wallet address");
      }

      throw new HttpsError("internal", "Failed to create Apple Pay order");
    }
  }
);
