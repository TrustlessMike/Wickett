import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {
  PRIVY_APP_ID,
  PRIVY_APP_SECRET,
  getAuthorizationKeyQuorumId,
  getWalletIdFromDid,
} from "../config/privy-config";
import {PrivyClient} from "@privy-io/node";
import {HELIUS_API_KEY, HELIUS_RPC_URL} from "../config/solana-config";
import {addAddressToWebhook} from "../utils/helius-webhook-manager";

/**
 * Cloud Function: Confirm delegation by adding authorization key as signer
 *
 * This function uses the user's JWT (access token) to authorize adding our
 * authorization key as an additional signer on their embedded wallet.
 *
 * Flow:
 * 1. User calls approveDelegationV2 → creates policy, returns pending delegation
 * 2. iOS gets user's access token and calls this function
 * 3. Server uses user_jwts to add auth key as additional_signer on wallet
 * 4. Delegation marked as "active"
 *
 * This approach works because:
 * - Swift SDK doesn't support addSessionSigner()
 * - But we can use the user's JWT to authorize the wallet update from server
 * - User still owns wallet (non-custodial)
 * - Auth key is just an additional signer with policy restrictions
 */
export const confirmDelegation = onCall(
  {
    secrets: [
      PRIVY_APP_ID,
      PRIVY_APP_SECRET,
      HELIUS_API_KEY,
      HELIUS_RPC_URL,
    ],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const {delegationId, privyAccessToken} = request.data as {
      delegationId: string;
      privyAccessToken: string;
    };

    if (!delegationId) {
      throw new HttpsError("invalid-argument", "delegationId is required");
    }

    if (!privyAccessToken) {
      throw new HttpsError("invalid-argument", "privyAccessToken is required");
    }

    logger.info(`🔐 Confirming delegation ${delegationId} for user ${userId}`);

    const db = getFirestore();

    // Get delegation config
    const delegationRef = db
      .collection("users")
      .doc(userId)
      .collection("delegations")
      .doc(delegationId);

    const delegationDoc = await delegationRef.get();

    if (!delegationDoc.exists) {
      throw new HttpsError("not-found", "Delegation not found");
    }

    const delegation = delegationDoc.data();

    if (delegation?.status !== "pending") {
      throw new HttpsError(
        "failed-precondition",
        `Delegation is not pending (status: ${delegation?.status})`
      );
    }

    // Get user data
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    if (!userData?.privyUserId) {
      throw new HttpsError(
        "failed-precondition",
        "User Privy user ID not found"
      );
    }

    // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
    const appId = PRIVY_APP_ID.value().trim();
    const appSecret = PRIVY_APP_SECRET.value().trim();

    // Get wallet ID
    const walletId = await getWalletIdFromDid(userData.privyUserId, appId, appSecret);
    logger.info(`✅ Resolved wallet ID: ${walletId}`);

    // Get authorization key quorum ID
    const authKeyQuorumId = getAuthorizationKeyQuorumId();
    logger.info(`🔑 Auth key quorum ID: ${authKeyQuorumId}`);

    // Initialize Privy client
    const privy = new PrivyClient({
      appId,
      appSecret,
    });

    try {
      logger.info("📝 Adding authorization key as additional signer...");

      // Use user's JWT to authorize adding the signer
      const updatedWallet = await privy.wallets().update(walletId, {
        additional_signers: [
          {
            signer_id: authKeyQuorumId,
            override_policy_ids: [delegation.privyPolicyId],
          },
        ],
        authorization_context: {
          user_jwts: [privyAccessToken],
        },
      });

      logger.info("✅ Authorization key added as signer!");

      // Add wallet to Helius webhook for payment monitoring
      if (userData.walletAddress) {
        try {
          logger.info("📡 Adding wallet to Helius webhook...");
          await addAddressToWebhook(userData.walletAddress);
          logger.info("✅ Wallet added to webhook");
        } catch (webhookError) {
          logger.warn("⚠️ Failed to add wallet to webhook (non-fatal):", webhookError);
        }
      }

      // Update delegation status to active
      await delegationRef.update({
        status: "active",
        requiresSignature: false,
        activatedAt: new Date(),
      });

      logger.info(`✅ Delegation ${delegationId} is now active!`);

      return {
        success: true,
        delegationId,
        status: "active",
        message: "Auto-convert is now enabled!",
      };

    } catch (error: any) {
      logger.error("❌ Failed to add authorization key as signer:", error);
      logger.error("   Error message:", error.message);
      logger.error("   Error name:", error.name);
      logger.error("   Error stack:", error.stack);

      // Log response details if available
      if (error.response) {
        logger.error("   Response status:", error.response.status);
        logger.error("   Response data:", JSON.stringify(error.response.data));
      }

      // Log error body if available (Privy SDK format)
      if (error.body) {
        logger.error("   Error body:", JSON.stringify(error.body));
      }

      // Log full error object
      logger.error("   Full error:", JSON.stringify(error, Object.getOwnPropertyNames(error)));

      // Check for specific error types
      if (error.message?.includes("401") || error.message?.includes("authorization")) {
        throw new HttpsError(
          "permission-denied",
          `Failed to authorize wallet update: ${error.message}. Please try logging in again.`
        );
      }

      throw new HttpsError(
        "internal",
        `Failed to confirm delegation: ${error.message || JSON.stringify(error)}`
      );
    }
  }
);
