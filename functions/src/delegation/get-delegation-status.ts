import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";

/**
 * Cloud Function: Get delegation status
 *
 * Returns user's current delegation configuration and status
 */
export const getDelegationStatus = onCall(async (request) => {
  const userId = request.auth?.uid;
  if (!userId) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  logger.info(`📊 Getting delegation status for user ${userId}`);

  const db = getFirestore();

  try {
    // DEBUG: First check ALL delegations (remove this after debugging)
    const allDelegationsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("delegations")
      .get();

    logger.info(`🔍 DEBUG: Total delegations found: ${allDelegationsSnapshot.size}`);
    let delegationIndex = 0;
    allDelegationsSnapshot.forEach((doc) => {
      delegationIndex++;
      const data = doc.data();
      logger.info(`   Delegation ${delegationIndex}: ID=${doc.id}, status=${data.status}, portfolio=${JSON.stringify(data.portfolio)}`);
    });

    // Get active delegation
    const delegationsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("delegations")
      .where("status", "==", "active")
      .limit(1)
      .get();

    logger.info(`🔍 DEBUG: Active delegations found: ${delegationsSnapshot.size}`);

    if (delegationsSnapshot.empty) {
      return {
        hasActiveDelegation: false,
        message: "No active delegation. Auto-convert is disabled.",
      };
    }

    const delegationDoc = delegationsSnapshot.docs[0];
    const delegation = delegationDoc.data();

    // Check if expired
    const now = new Date();
    const expiresAt = delegation.expiresAt?.toDate();

    if (expiresAt && expiresAt < now) {
      // Mark as expired
      await delegationDoc.ref.update({
        status: "expired",
        expiredAt: now,
      });

      return {
        hasActiveDelegation: false,
        message: "Delegation has expired. Please re-enable auto-convert.",
      };
    }

    // Calculate remaining daily limit
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // Get today's swaps
    const swapsSnapshot = await db
      .collection("auto_swap_logs")
      .where("userId", "==", userId)
      .where("timestamp", ">=", today)
      .get();

    const todayVolumeUsd = swapsSnapshot.docs.reduce(
      (sum, doc) => sum + (doc.data().totalValueSwapped || 0),
      0
    );

    const remainingDailyLimitUsd = delegation.dailyLimitUsd - todayVolumeUsd;

    logger.info(`✅ Active delegation found for user ${userId}`);
    logger.info(`📊 Swaps executed: ${delegation.totalSwapsExecuted}`);
    logger.info(`💰 Total volume: $${delegation.totalVolumeSwappedUsd}`);
    logger.info(`📈 Today's volume: $${todayVolumeUsd}`);
    logger.info(`💸 Remaining daily limit: $${remainingDailyLimitUsd}`);

    // Add IDs to portfolio items if they don't have them (for iOS Identifiable conformance)
    const portfolioWithIds = delegation.portfolio.map((item: any) => ({
      ...item,
      id: item.id || `${item.token}_${item.symbol}`, // Use existing ID or generate from token/symbol
    }));

    // Check if this is a V2 (Privy) delegation or legacy SPL delegation
    const isPrivyDelegation = !!delegation.privyPolicyId;

    return {
      hasActiveDelegation: true,
      delegation: {
        portfolio: portfolioWithIds,
        maxSwapAmountUsd: delegation.maxSwapAmountUsd,
        dailyLimitUsd: delegation.dailyLimitUsd,
        expiresAt: expiresAt?.toISOString(),
        delegateWallet: delegation.delegateWallet || null, // Legacy SPL only
        privyPolicyId: delegation.privyPolicyId || null, // V2 Privy only
        createdAt: delegation.createdAt?.toDate()?.toISOString(),
        lastSwapAt: delegation.lastSwapAt?.toDate()?.toISOString(),
        totalSwapsExecuted: delegation.totalSwapsExecuted,
        totalVolumeSwappedUsd: delegation.totalVolumeSwappedUsd,
        todayVolumeUsd,
        remainingDailyLimitUsd,
      },
    };

  } catch (error) {
    logger.error("❌ Failed to get delegation status:", error);
    throw new HttpsError("internal", `Failed to get delegation status: ${error}`);
  }
});
