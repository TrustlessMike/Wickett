import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import axios from "axios";
import { JUPITER_API_KEY } from "./jupiter-client";

interface ExecuteJupiterSwapData {
  signedTransaction: string; // Base64-encoded signed transaction
  requestId: string; // From getJupiterSwapTransaction response
}

/**
 * Cloud Function: executeJupiterSwap
 *
 * Executes a signed Jupiter Ultra swap transaction.
 * Uses Jupiter's /execute endpoint for reliable transaction landing.
 */
export const executeJupiterSwap = onCall(
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

    const { signedTransaction, requestId } = data as ExecuteJupiterSwapData;

    // Validate inputs
    if (!signedTransaction || typeof signedTransaction !== "string") {
      throw new HttpsError("invalid-argument", "signedTransaction is required");
    }
    if (!requestId || typeof requestId !== "string") {
      throw new HttpsError("invalid-argument", "requestId is required");
    }

    try {
      logger.info(`🚀 Executing Jupiter swap`);
      logger.info(`   Request ID: ${requestId}`);

      const apiKey = JUPITER_API_KEY.value();
      if (!apiKey) {
        throw new Error("Jupiter API key not configured");
      }

      // Call Jupiter Ultra API /execute endpoint
      const response = await axios.post(
        "https://api.jup.ag/ultra/v1/execute",
        {
          signedTransaction,
          requestId,
        },
        {
          headers: {
            "Content-Type": "application/json",
            "x-api-key": apiKey,
          },
          timeout: 60000, // 60 second timeout for execution
        }
      );

      const result = response.data as { signature?: string; transactionId?: string; status?: string };
      logger.info(`✅ Jupiter swap executed: ${result.signature || result.transactionId}`);

      return {
        success: true,
        data: {
          signature: result.signature || result.transactionId || "",
          status: result.status || "confirmed",
        },
      };
    } catch (error: any) {
      logger.error("❌ Error executing Jupiter swap:", error);

      // Parse Jupiter API error response
      if (error.response?.data) {
        const jupiterError = error.response.data;
        logger.error("Jupiter API error:", jupiterError);
        throw new HttpsError(
          "internal",
          `Swap failed: ${jupiterError.error || jupiterError.message || "Unknown error"}`
        );
      }

      throw new HttpsError(
        "internal",
        `Failed to execute swap: ${error.message}`
      );
    }
  }
);
