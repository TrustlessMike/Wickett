import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: updateWalletAddress
 * Updates a user's wallet address in Firestore
 * Called by iOS after Privy creates the embedded Solana wallet
 */
export const updateWalletAddress = onCall(
  {
    invoker: "public",
  },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = auth.uid;
    const { walletAddress } = data as { walletAddress: string };

    // Validate input
    if (!walletAddress || typeof walletAddress !== "string") {
      throw new HttpsError("invalid-argument", "Wallet address is required");
    }

    // Basic validation for Solana wallet address format (base58, 32-44 chars)
    if (walletAddress.length < 32 || walletAddress.length > 44) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid Solana wallet address format"
      );
    }

    try {
      const db = getFirestore();

      // Update user document with wallet address
      await db
        .collection("users")
        .doc(userId)
        .update({
          walletAddress: walletAddress,
          updatedAt: FieldValue.serverTimestamp(),
        });

      logger.info(`✅ Updated wallet address for user ${userId}: ${walletAddress}`);

      return {
        success: true,
        data: {
          walletAddress,
        },
      };
    } catch (error: any) {
      logger.error("❌ Error updating wallet address:", error);
      throw new HttpsError(
        "internal",
        `Failed to update wallet address: ${error.message}`
      );
    }
  }
);
