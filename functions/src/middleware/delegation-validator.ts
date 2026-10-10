import * as logger from "firebase-functions/logger";
import {HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";

/**
 * Validation result for delegation checks
 */
export interface DelegationValidation {
  isValid: boolean;
  delegation: any | null;
  reason?: string;
}

/**
 * Validate that user has active delegation within limits
 *
 * @param userId - User ID
 * @param swapValueUsd - USD value of the swap
 * @param existingDelegation - Optional pre-fetched delegation data to avoid redundant queries
 */
export async function validateDelegation(
  userId: string,
  swapValueUsd: number,
  existingDelegation?: {delegation: any; delegationDoc: any}
): Promise<DelegationValidation> {
  const db = getFirestore();

  try {
    // Use existing delegation if provided, otherwise query
    let delegationDoc;
    let delegation;

    if (existingDelegation) {
      delegationDoc = existingDelegation.delegationDoc;
      delegation = existingDelegation.delegation;
      logger.info("✅ Using cached delegation data (query saved)");
    } else {
      // Get active delegation
      const delegationsSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("delegations")
        .where("status", "==", "active")
        .limit(1)
        .get();

      if (delegationsSnapshot.empty) {
        return {
          isValid: false,
          delegation: null,
          reason: "No active delegation found",
        };
      }

      delegationDoc = delegationsSnapshot.docs[0];
      delegation = delegationDoc.data();
    }

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
        isValid: false,
        delegation: null,
        reason: "Delegation has expired",
      };
    }

    // Check per-swap limit
    if (swapValueUsd > delegation.maxSwapAmountUsd) {
      return {
        isValid: false,
        delegation,
        reason: `Swap amount $${swapValueUsd} exceeds per-swap limit of $${delegation.maxSwapAmountUsd}`,
      };
    }

    // Check daily limit
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    let todayVolumeUsd = 0;
    try {
      const swapsSnapshot = await db
        .collection("auto_swap_logs")
        .where("userId", "==", userId)
        .where("timestamp", ">=", today)
        .get();

      todayVolumeUsd = swapsSnapshot.docs.reduce(
        (sum, doc) => sum + (doc.data().totalValueSwapped || 0),
        0
      );
    } catch (error: any) {
      // Gracefully handle missing index - assume 0 volume for new users
      if (error.code === 9 || error.message?.includes("index")) {
        logger.warn("⚠️  auto_swap_logs index not found, assuming 0 daily volume (first-time user)");
        todayVolumeUsd = 0;
      } else {
        throw error;
      }
    }

    if (todayVolumeUsd + swapValueUsd > delegation.dailyLimitUsd) {
      return {
        isValid: false,
        delegation,
        reason: `Daily limit exceeded: $${todayVolumeUsd.toFixed(2)} + $${swapValueUsd} > $${delegation.dailyLimitUsd}`,
      };
    }

    // All checks passed
    logger.info(`✅ Delegation validation passed for user ${userId}`);
    logger.info(`   Swap amount: $${swapValueUsd}`);
    logger.info(`   Today's volume: $${todayVolumeUsd}`);
    logger.info(`   Remaining daily limit: $${delegation.dailyLimitUsd - todayVolumeUsd}`);

    return {
      isValid: true,
      delegation,
    };

  } catch (error) {
    logger.error("❌ Delegation validation failed:", error);
    throw new HttpsError("internal", `Delegation validation failed: ${error}`);
  }
}

/**
 * Check hourly swap rate limits for auto-convert (60-minute window)
 */
export async function checkHourlySwapLimit(userId: string): Promise<{
  allowed: boolean;
  recentSwaps: number;
  limit: number;
}> {
  const db = getFirestore();
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);

  const recentSwapsSnapshot = await db
    .collection("auto_swap_logs")
    .where("userId", "==", userId)
    .where("timestamp", ">=", oneHourAgo)
    .get();

  const recentSwaps = recentSwapsSnapshot.size;
  const limit = 15;

  return {
    allowed: recentSwaps < limit,
    recentSwaps,
    limit,
  };
}
