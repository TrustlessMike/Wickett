import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, Timestamp} from "firebase-admin/firestore";

/**
 * Activity item returned to the client
 */
export interface ActivityItem {
  id: string;
  type: "auto_convert" | "payment_sent" | "payment_received" | "request_sent" | "request_received";
  title: string;
  subtitle: string;
  amount: number;
  timestamp: Timestamp;
  status: "completed" | "pending" | "failed";
  icon: string;
}

/**
 * Cloud Function: getUserActivity
 * Aggregates user activity from multiple Firestore collections
 * Returns user-friendly activity items for display
 */
export const getUserActivity = onCall(
  {
    enforceAppCheck: false,
  },
  async (request) => {
    const userId = request.auth?.uid;

    if (!userId) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    logger.info(`📋 Fetching activity for user: ${userId}`);

    const db = getFirestore();
    const activities: ActivityItem[] = [];

    try {
      // 1. Fetch auto-swap logs
      const autoSwapSnapshot = await db
        .collection("auto_swap_logs")
        .where("userId", "==", userId)
        .orderBy("timestamp", "desc")
        .limit(50)
        .get();

      for (const doc of autoSwapSnapshot.docs) {
        const data = doc.data();
        const inputSymbol = data.input?.symbol || "tokens";
        const inputAmount = data.input?.amount || 0;
        const outputSummary = formatOutputs(data.outputs || []);

        activities.push({
          id: doc.id,
          type: "auto_convert",
          title: "Converted to your portfolio",
          subtitle: `Received ${formatAmount(inputAmount)} ${inputSymbol}${outputSummary}`,
          amount: data.input?.valueUsd || 0,
          timestamp: data.timestamp,
          status: data.status === "success" ? "completed" : "failed",
          icon: "arrow.triangle.2.circlepath",
        });
      }

      // 2. Fetch payment requests created by user (sent requests)
      const sentRequestsSnapshot = await db
        .collection("payment_requests")
        .where("requesterId", "==", userId)
        .orderBy("createdAt", "desc")
        .limit(30)
        .get();

      for (const doc of sentRequestsSnapshot.docs) {
        const data = doc.data();
        const recipientName = data.recipientName || "someone";
        const amount = data.amount || 0;
        const currency = data.currency || data.tokenSymbol || "USD";

        activities.push({
          id: doc.id,
          type: "request_sent",
          title: `Requested from @${recipientName}`,
          subtitle: formatCurrency(amount, currency),
          amount: amount,
          timestamp: data.createdAt,
          status: mapRequestStatus(data.status),
          icon: "arrow.up.circle",
        });
      }

      // 3. Fetch received requests (requests where user was asked to pay)
      const receivedRequestsSnapshot = await db
        .collection("users")
        .doc(userId)
        .collection("received_requests")
        .orderBy("viewedAt", "desc")
        .limit(30)
        .get();

      for (const doc of receivedRequestsSnapshot.docs) {
        const receivedData = doc.data();
        const requestId = receivedData.requestId;

        // Get the actual request details
        const requestDoc = await db
          .collection("payment_requests")
          .doc(requestId)
          .get();

        if (requestDoc.exists) {
          const data = requestDoc.data()!;
          const requesterName = data.requesterName || "someone";
          const amount = data.amount || 0;
          const currency = data.currency || data.tokenSymbol || "USD";

          activities.push({
            id: doc.id,
            type: "request_received",
            title: `Request from @${requesterName}`,
            subtitle: `${formatCurrency(amount, currency)}${data.status === "pending" ? " - pay now" : ""}`,
            amount: amount,
            timestamp: data.createdAt,
            status: mapRequestStatus(receivedData.status || data.status),
            icon: "arrow.down.circle",
          });
        }
      }

      // 4. Fetch payments where user was the payer (request fulfillment)
      const paidRequestsSnapshot = await db
        .collection("payment_requests")
        .where("paidBy", "==", userId)
        .where("status", "==", "paid")
        .orderBy("paidAt", "desc")
        .limit(30)
        .get();

      for (const doc of paidRequestsSnapshot.docs) {
        const data = doc.data();
        const requesterName = data.requesterName || "someone";
        const amount = data.amount || 0;
        const currency = data.currency || data.tokenSymbol || "USD";

        activities.push({
          id: `payment_${doc.id}`,
          type: "payment_sent",
          title: `Sent to @${requesterName}`,
          subtitle: formatCurrency(amount, currency),
          amount: amount,
          timestamp: data.paidAt || data.createdAt,
          status: "completed",
          icon: "arrow.up.circle.fill",
        });
      }

      // 5. Fetch direct wallet transfers (from SendView)
      try {
        const directTransfersSnapshot = await db
          .collection("solana_transactions")
          .where("user_id", "==", userId)
          .where("transaction_type", "in", ["sol_transfer", "spl_transfer"])
          .orderBy("timestamp", "desc")
          .limit(30)
          .get();

        for (const doc of directTransfersSnapshot.docs) {
          const data = doc.data();
          const amountUsd = data.amount_usd || 0;

          // Skip zero-amount transactions
          if (amountUsd < 0.01) continue;

          // Skip if this is already tracked via payment_requests
          const existingPayment = activities.find(
            (a) => a.id === `payment_${doc.id}` || a.id === doc.id
          );
          if (existingPayment) continue;

          const tokenType = data.transaction_type === "sol_transfer" ? "SOL" : "tokens";

          activities.push({
            id: doc.id,
            type: "payment_sent",
            title: `Sent ${tokenType}`,
            subtitle: data.recipient_display || shortenAddress(data.recipient_address) || "wallet",
            amount: amountUsd,
            timestamp: data.timestamp,
            status: data.status === "success" ? "completed" : "failed",
            icon: "arrow.up.circle.fill",
          });
        }
      } catch (indexError) {
        // Index may not be ready yet - log and continue without direct transfers
        logger.warn("⚠️ Could not fetch solana_transactions (index may be building):", indexError);
      }

      // Sort all activities by timestamp (most recent first)
      activities.sort((a, b) => {
        const timeA = a.timestamp?.toMillis?.() || 0;
        const timeB = b.timestamp?.toMillis?.() || 0;
        return timeB - timeA;
      });

      // Limit to 100 most recent
      const limitedActivities = activities.slice(0, 100);

      logger.info(`✅ Returning ${limitedActivities.length} activity items`);

      return {
        activities: limitedActivities,
        hasMore: activities.length > 100,
      };
    } catch (error) {
      logger.error("❌ Error fetching user activity:", error);
      throw new HttpsError(
        "internal",
        `Failed to fetch activity: ${(error as Error).message}`
      );
    }
  }
);

/**
 * Format output tokens summary
 */
function formatOutputs(outputs: Array<{symbol: string; amount: number}>): string {
  if (!outputs || outputs.length === 0) return "";

  const summary = outputs
    .map((o) => `${formatAmount(o.amount)} ${o.symbol}`)
    .join(", ");

  return ` → ${summary}`;
}

/**
 * Format amount with appropriate precision
 */
function formatAmount(amount: number): string {
  if (amount >= 1000) {
    return amount.toLocaleString("en-US", {maximumFractionDigits: 0});
  } else if (amount >= 1) {
    return amount.toLocaleString("en-US", {maximumFractionDigits: 2});
  } else {
    return amount.toLocaleString("en-US", {maximumFractionDigits: 4});
  }
}

/**
 * Format currency amount
 */
function formatCurrency(amount: number, currency: string): string {
  if (currency === "USD" || currency === "EUR" || currency === "GBP") {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: currency,
    }).format(amount);
  }
  return `${formatAmount(amount)} ${currency}`;
}

/**
 * Map request status to activity status
 */
function mapRequestStatus(status: string): "completed" | "pending" | "failed" {
  switch (status) {
  case "paid":
    return "completed";
  case "pending":
    return "pending";
  case "expired":
  case "rejected":
    return "failed";
  default:
    return "pending";
  }
}

/**
 * Shorten wallet address for display
 */
function shortenAddress(address: string | undefined): string {
  if (!address) return "";
  if (address.length <= 10) return address;
  return `${address.slice(0, 4)}...${address.slice(-4)}`;
}
