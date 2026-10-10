import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {HELIUS_API_KEY, HELIUS_RPC_URL} from "../config/solana-config";
import {removeAddressFromWebhook} from "../utils/helius-webhook-manager";

/**
 * Cloud Function: Revoke Privy delegation for auto-convert
 *
 * For Privy V2 delegation, there's no on-chain delegation to revoke.
 * We simply update the Firestore status to "revoked" and optionally
 * remove the wallet from the Helius webhook.
 *
 * The Privy policy will expire naturally based on its expiration time.
 */
export const revokeDelegationV2 = onCall(
  {
    secrets: [HELIUS_RPC_URL, HELIUS_API_KEY],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    logger.info(`🔒 Revoking Privy delegation for user ${userId}`);

    const db = getFirestore();

    // Get user's wallet address
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    if (!userData?.walletAddress) {
      throw new HttpsError("failed-precondition", "User wallet not found");
    }

    // Get active delegation
    const delegationsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("delegations")
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (delegationsSnapshot.empty) {
      throw new HttpsError("not-found", "No active delegation found");
    }

    const delegationDoc = delegationsSnapshot.docs[0];
    const delegation = delegationDoc.data();

    logger.info(`📋 Revoking delegation: ${delegationDoc.id}`);
    logger.info(`   Policy ID: ${delegation.privyPolicyId}`);

    try {
      // Mark delegation as revoked in Firestore
      await delegationDoc.ref.update({
        status: "revoked",
        revokedAt: FieldValue.serverTimestamp(),
      });

      logger.info(`✅ Delegation marked as revoked in Firestore`);

      // Remove user's wallet from Helius webhook (optional - they may still receive payments)
      try {
        await removeAddressFromWebhook(userData.walletAddress);
        logger.info(`✅ Removed ${userData.walletAddress} from Helius webhook`);
      } catch (error) {
        logger.warn(`⚠️ Failed to remove address from webhook (non-critical): ${error}`);
        // Don't fail the whole operation if webhook update fails
      }

      // Note: We don't delete the Privy policy - it will expire naturally
      // Deleting policies is not commonly supported and the policy won't be used
      // once the delegation status is "revoked" in Firestore

      return {
        success: true,
        message: "Auto-convert disabled successfully. Your delegation has been revoked.",
        delegationId: delegationDoc.id,
        policyId: delegation.privyPolicyId,
      };

    } catch (error) {
      logger.error("❌ Failed to revoke delegation:", error);
      throw new HttpsError("internal", `Failed to revoke delegation: ${error}`);
    }
  }
);
