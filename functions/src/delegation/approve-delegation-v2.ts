import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {
  PRIVY_APP_ID,
  PRIVY_APP_SECRET,
  PRIVY_AUTHORIZATION_PRIVATE_KEY,
  createAutoSwapPolicy,
  getAuthorizationKeyQuorumId,
  getWalletIdFromDid,
} from "../config/privy-config";
import {HELIUS_API_KEY, HELIUS_RPC_URL} from "../config/solana-config";
import {addAddressToWebhook} from "../utils/helius-webhook-manager";

/**
 * Delegation configuration stored in Firestore (Privy version)
 */
export interface DelegationConfigV2 {
  userId: string;
  status: "pending" | "active" | "revoked" | "expired";

  // Portfolio preferences
  portfolio: {
    token: string;      // Token mint address
    symbol: string;     // e.g., "SOL", "USDC", "BONK"
    percentage: number; // e.g., 50, 30, 20 (must sum to 100)
  }[];

  // Security constraints
  maxSwapAmountUsd: number;  // Max USD value per swap
  dailyLimitUsd: number;     // Max USD value per day
  expiresAt: FirebaseFirestore.Timestamp;

  // Privy-specific fields
  privyPolicyId: string;        // Privy policy ID
  privyKeyQuorumId: string;     // Privy key quorum ID
  requiresSignature: boolean;   // Whether user needs to approve in iOS app

  // Tracking
  createdAt: FirebaseFirestore.Timestamp;
  lastSwapAt?: FirebaseFirestore.Timestamp;
  totalSwapsExecuted: number;
  totalVolumeSwappedUsd: number;

  // Balance snapshots (to differentiate incoming vs existing)
  balanceSnapshots: {
    [tokenMint: string]: number;  // Balance when delegation was approved
  };
}

/**
 * Request to approve delegation (Privy version)
 */
interface ApproveDelegationRequestV2 {
  portfolio: {
    token: string;
    symbol: string;
    percentage: number;
  }[];
  maxSwapAmountUsd: number;
  dailyLimitUsd: number;
  expirationDays: number;  // 30, 90, or 365
  privyAccessToken: string; // User's Privy access token for signing wallet update
}

/**
 * Cloud Function: Approve delegation for auto-convert using Privy authorization keys
 *
 * This function creates a Privy policy and immediately activates the delegation.
 * Since wallets are now created server-side with the auth key as an additional signer
 * from the start, we don't need user JWT authorization to add the signer.
 *
 * Flow:
 * 1. Validate portfolio allocation
 * 2. Check if wallet has auth key as signer
 * 3. Create Privy policy with swap restrictions
 * 4. Update wallet to use policy for auth key's override_policy_ids
 * 5. Store delegation config in Firestore (status: "active")
 * 6. Add wallet to Helius webhook for payment monitoring
 *
 * NOTE: This simplified flow works because wallets are created via createServerWallet
 * which adds our authorization key as an additional_signer from the start.
 */
export const approveDelegationV2 = onCall(
  {
    secrets: [
      PRIVY_APP_ID,
      PRIVY_APP_SECRET,
      PRIVY_AUTHORIZATION_PRIVATE_KEY,
      HELIUS_API_KEY,
      HELIUS_RPC_URL,
    ],
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const data = request.data as ApproveDelegationRequestV2;

    // Validate portfolio allocation
    if (!data.portfolio || data.portfolio.length === 0) {
      throw new HttpsError("invalid-argument", "Portfolio allocation required");
    }

    const totalPercentage = data.portfolio.reduce((sum, p) => sum + p.percentage, 0);
    if (Math.abs(totalPercentage - 100) > 0.01) {
      throw new HttpsError(
        "invalid-argument",
        `Portfolio percentages must sum to 100%, got ${totalPercentage}%`
      );
    }

    // Validate limits
    if (data.maxSwapAmountUsd <= 0 || data.dailyLimitUsd <= 0) {
      throw new HttpsError("invalid-argument", "Limits must be positive");
    }

    if (data.expirationDays !== 30 && data.expirationDays !== 90 && data.expirationDays !== 365) {
      throw new HttpsError("invalid-argument", "Expiration must be 30, 90, or 365 days");
    }

    // Validate Privy access token is provided
    if (!data.privyAccessToken) {
      throw new HttpsError("invalid-argument", "Privy access token required for wallet update authorization");
    }

    logger.info(`📝 Creating Privy delegation for user ${userId}`);
    logger.info(`Portfolio: ${JSON.stringify(data.portfolio)}`);
    logger.info(`Limits: $${data.maxSwapAmountUsd} per swap, $${data.dailyLimitUsd} daily`);
    logger.info(`Expires in ${data.expirationDays} days`);

    const db = getFirestore();

    // Get user's wallet address and Privy DID
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    if (!userData?.walletAddress) {
      throw new HttpsError("failed-precondition", "User wallet not found");
    }

    if (!userData?.privyUserId) {
      throw new HttpsError(
        "failed-precondition",
        "User Privy user ID not found. Ensure wallet was created via Privy."
      );
    }

    // Look up actual wallet ID from Privy API using the user ID AND wallet address
    // This is critical for users with multiple wallets - we need the right one
    // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
    const appId = PRIVY_APP_ID.value().trim();
    const appSecret = PRIVY_APP_SECRET.value().trim();
    const walletId = await getWalletIdFromDid(userData.privyUserId, appId, appSecret, userData.walletAddress);
    logger.info(`✅ Resolved wallet ID: ${walletId} for address ${userData.walletAddress}`);

    try {
      // Calculate expiration timestamp
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + data.expirationDays);
      const expirationTimestamp = Math.floor(expiresAt.getTime() / 1000);

      // Create Privy policy for this user
      // Policy name must be < 50 chars (Privy validation)
      // Use short hash of userId + timestamp for uniqueness
      const shortName = `swap-${userId.slice(-8)}-${Date.now().toString().slice(-6)}`;
      logger.info("📋 Creating Privy policy...");
      const policyId = await createAutoSwapPolicy({
        name: shortName,
        maxSwapAmountUsd: data.maxSwapAmountUsd,
        expirationTimestamp,
        allowedTokenMints: data.portfolio.map(p => p.token),
      });

      logger.info(`✅ Privy policy created: ${policyId}`);

      // Get key quorum ID
      const keyQuorumId = getAuthorizationKeyQuorumId();

      // Check if wallet was created server-side (has auth key from start)
      // Note: Firestore may store this as 1/0 or true/false depending on how it was set
      const walletHasAuthKey = Boolean(userData.walletHasAuthKey);
      logger.info(`   Wallet has auth key: ${walletHasAuthKey} (raw value: ${userData.walletHasAuthKey})`);

      // Check if wallet has auth key - if so, we need to ensure it has a policy attached
      if (walletHasAuthKey) {
        logger.info("✅ Wallet has auth key - checking if policy update needed");

        // Check if wallet already has a policy via REST API
        const walletCheckResponse = await fetch(`https://api.privy.io/v1/wallets/${walletId}`, {
          headers: {
            "Authorization": `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`,
            "privy-app-id": appId,
          },
        });

        if (walletCheckResponse.ok) {
          const walletData = await walletCheckResponse.json();
          const authKeySigner = walletData.additional_signers?.find(
            (s: any) => s.signer_id === keyQuorumId
          );

          if (authKeySigner?.override_policy_ids?.length > 0) {
            logger.info(`✅ Auth key already has policy: ${authKeySigner.override_policy_ids[0]}`);
          } else {
            // Auth key has no policy - use user JWT to add one
            logger.info("📝 Auth key has no policy - using user JWT to add policy...");

            const updateWalletResponse = await fetch(`https://api.privy.io/v1/wallets/${walletId}`, {
              method: "PATCH",
              headers: {
                "Authorization": `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`,
                "privy-app-id": appId,
                "Content-Type": "application/json",
                "privy-user-access-token": data.privyAccessToken, // User's JWT for authorization
              },
              body: JSON.stringify({
                additional_signers: [
                  {
                    signer_id: keyQuorumId,
                    override_policy_ids: [policyId],
                  },
                ],
              }),
            });

            if (updateWalletResponse.ok) {
              const updatedWallet = await updateWalletResponse.json();
              logger.info("✅ Wallet updated with policy!");
              logger.info(`   Additional signers: ${JSON.stringify(updatedWallet.additional_signers)}`);
            } else {
              const error = await updateWalletResponse.text();
              logger.warn(`⚠️ Failed to update wallet with policy: ${error}`);
              logger.info("📝 Continuing anyway - policy will be enforced via Firestore");
            }
          }
        }
      } else {
        // Wallet was created client-side, needs confirmDelegation flow
        logger.warn("⚠️ Wallet created client-side - auth key needs to be added manually");
        throw new HttpsError(
          "failed-precondition",
          "Wallet doesn't have authorization key. Please recreate your account with server-side wallet."
        );
      }

      // Get current token balances for snapshot
      // Note: We'll initialize all to 0 and update them when user receives tokens
      const balanceSnapshots: {[key: string]: number} = {};
      for (const portfolioItem of data.portfolio) {
        balanceSnapshots[portfolioItem.token] = 0;
      }

      // CLEANUP: Delete old delegations before creating new one
      logger.info("🧹 Cleaning up old delegations...");

      // Delete all non-active delegations (pending, revoked, expired)
      const oldDelegations = await db
        .collection("users")
        .doc(userId)
        .collection("delegations")
        .where("status", "in", ["pending", "revoked", "expired"])
        .get();

      if (!oldDelegations.empty) {
        const deletePromises = oldDelegations.docs.map(doc => {
          logger.info(`  Deleting old delegation: ${doc.id} (status: ${doc.data().status})`);
          return doc.ref.delete();
        });
        await Promise.all(deletePromises);
        logger.info(`✅ Deleted ${oldDelegations.size} old delegation(s)`);
      }

      // Revoke any active delegations (user is creating a new one)
      const activeDelegations = await db
        .collection("users")
        .doc(userId)
        .collection("delegations")
        .where("status", "==", "active")
        .get();

      if (!activeDelegations.empty) {
        for (const doc of activeDelegations.docs) {
          logger.info(`  Revoking old active delegation: ${doc.id}`);
          await doc.ref.update({status: "revoked"});
        }
        logger.info(`✅ Revoked ${activeDelegations.size} active delegation(s)`);
      }

      // Add wallet to Helius webhook for payment monitoring
      try {
        logger.info("📡 Adding wallet to Helius webhook...");
        await addAddressToWebhook(userData.walletAddress);
        logger.info("✅ Wallet added to webhook");
      } catch (webhookError) {
        logger.warn("⚠️ Failed to add wallet to webhook (non-fatal):", webhookError);
      }

      // Create delegation config in Firestore - ACTIVE immediately
      const delegationConfig: Partial<DelegationConfigV2> = {
        userId,
        status: "active", // Active immediately since auth key is already a signer
        portfolio: data.portfolio,
        maxSwapAmountUsd: data.maxSwapAmountUsd,
        dailyLimitUsd: data.dailyLimitUsd,
        expiresAt: expiresAt as any,
        privyPolicyId: policyId,
        privyKeyQuorumId: keyQuorumId,
        requiresSignature: false, // No user signature needed
        createdAt: FieldValue.serverTimestamp() as any,
        totalSwapsExecuted: 0,
        totalVolumeSwappedUsd: 0,
        balanceSnapshots,
      };

      const delegationRef = await db
        .collection("users")
        .doc(userId)
        .collection("delegations")
        .add(delegationConfig);

      logger.info(`✅ Delegation created and ACTIVE: ${delegationRef.id}`);

      return {
        success: true,
        delegationId: delegationRef.id,
        policyId,
        keyQuorumId,
        status: "active",
        expiresAt: expiresAt.toISOString(),
        message: "Auto-convert is now enabled!",
      };

    } catch (error: any) {
      logger.error("❌ Failed to create Privy delegation:", error);
      if (error instanceof HttpsError) {
        throw error;
      }
      throw new HttpsError("internal", `Failed to create delegation: ${error.message || error}`);
    }
  }
);
