import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { jupiterClient, JUPITER_API_KEY } from "./jupiter-client";

interface GetJupiterSwapTransactionData {
  inputMint: string;
  outputMint: string;
  amount: number; // Amount in smallest unit (lamports)
  userWalletAddress: string;
  slippageBps?: number;
}

/**
 * Cloud Function: getJupiterSwapTransaction
 *
 * Simplified swap function that returns:
 * - Quote details (for UI display)
 * - Unsigned transaction (for Privy to sign + sponsor gas)
 *
 * This replaces the old sponsorJupiterSwap which did unnecessary
 * fee payer manipulation. Privy handles gas sponsorship.
 */
export const getJupiterSwapTransaction = onCall(
  {
    secrets: [JUPITER_API_KEY],
    invoker: "public",
  },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const {
      inputMint,
      outputMint,
      amount,
      userWalletAddress,
      slippageBps = 50,
    } = data as GetJupiterSwapTransactionData;

    // Validate inputs
    if (!inputMint || typeof inputMint !== "string") {
      throw new HttpsError("invalid-argument", "inputMint is required");
    }
    if (!outputMint || typeof outputMint !== "string") {
      throw new HttpsError("invalid-argument", "outputMint is required");
    }
    if (!amount || amount <= 0) {
      throw new HttpsError("invalid-argument", "amount must be greater than 0");
    }
    if (!userWalletAddress || typeof userWalletAddress !== "string") {
      throw new HttpsError("invalid-argument", "userWalletAddress is required");
    }

    try {
      logger.info(`🔄 Getting Jupiter swap transaction (Ultra API)`);
      logger.info(`   From: ${inputMint}`);
      logger.info(`   To: ${outputMint}`);
      logger.info(`   Amount: ${amount}`);
      logger.info(`   User: ${userWalletAddress}`);

      // Use Ultra API - combined quote + transaction in one call
      const order = await jupiterClient.getOrder({
        inputMint,
        outputMint,
        amount,
        taker: userWalletAddress,
        slippageBps,
      });

      logger.info(`✅ Ultra order received: ${order.inAmount} → ${order.outAmount}`);

      // Return quote info + unsigned transaction
      // iOS will use Privy to sign this (Privy sponsors gas)
      return {
        success: true,
        data: {
          // Quote details for UI
          inputMint: order.inputMint,
          outputMint: order.outputMint,
          inAmount: order.inAmount,
          outAmount: order.outAmount,
          priceImpactPct: "0", // Ultra API doesn't return this directly
          slippageBps,
          // Unsigned transaction for Privy to sign
          transaction: order.transaction,
          requestId: order.requestId,
        },
      };
    } catch (error: any) {
      logger.error("❌ Error getting Jupiter swap transaction:", error);
      throw new HttpsError(
        "internal",
        `Failed to get swap transaction: ${error.message}`
      );
    }
  }
);
