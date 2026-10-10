import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { PaymentRequest, RequestStatus } from "./types";
import { sendPaymentRequestNotification } from "../utils/push-notifications";

interface CreateAndSendFiatRequestData {
  amount: number;
  currency: string;
  portfolio: Array<{
    id: string;
    token: string;
    symbol: string;
    percentage: number;
  }>;
  isFixedAmount: boolean;
  memo: string;
  recipientUserId: string;
}

/**
 * Cloud Function: createAndSendFiatRequest
 * Creates a fiat payment request AND sends it to recipient in ONE call
 * ~50% faster than calling createFiatPaymentRequest + sendRequestNotification separately
 */
export const createAndSendFiatRequest = onCall(
  {
    invoker: "public",
  },
  async (request) => {
    const { auth, data } = request;

    if (!auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = auth.uid;
    const { amount, currency, portfolio, isFixedAmount, memo, recipientUserId } =
      data as CreateAndSendFiatRequestData;

    // Validate input
    if (!amount || amount <= 0) {
      throw new HttpsError("invalid-argument", "Amount must be greater than 0");
    }

    if (!currency || typeof currency !== "string") {
      throw new HttpsError("invalid-argument", "Currency is required");
    }

    if (!Array.isArray(portfolio) || portfolio.length === 0) {
      throw new HttpsError("invalid-argument", "Portfolio allocation is required");
    }

    const totalPercentage = portfolio.reduce((sum, a) => sum + a.percentage, 0);
    if (Math.abs(totalPercentage - 100) > 0.01) {
      throw new HttpsError(
        "invalid-argument",
        `Portfolio must total 100% (current: ${totalPercentage}%)`
      );
    }

    if (typeof isFixedAmount !== "boolean") {
      throw new HttpsError("invalid-argument", "isFixedAmount must be a boolean");
    }

    if (!memo || typeof memo !== "string") {
      throw new HttpsError("invalid-argument", "Memo is required");
    }

    if (!recipientUserId || typeof recipientUserId !== "string") {
      throw new HttpsError("invalid-argument", "Recipient user ID is required");
    }

    if (userId === recipientUserId) {
      throw new HttpsError("invalid-argument", "Cannot send request to yourself");
    }

    try {
      const db = getFirestore();

      // Fetch user and recipient in PARALLEL
      const [userDoc, recipientDoc] = await Promise.all([
        db.collection("users").doc(userId).get(),
        db.collection("users").doc(recipientUserId).get(),
      ]);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      if (!recipientDoc.exists) {
        throw new HttpsError("not-found", "Recipient user not found");
      }

      const userData = userDoc.data()!;
      const recipientData = recipientDoc.data()!;
      const requesterName = userData.displayName || "Unknown";
      const requesterAddress = userData.walletAddress;
      const recipientName = recipientData.displayName || "Unknown";

      if (!requesterAddress) {
        throw new HttpsError("failed-precondition", "User does not have a wallet address");
      }

      // Create payment request
      const now = Timestamp.now();
      const expiresAt = Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000);

      const paymentRequest: PaymentRequest = {
        requesterId: userId,
        requesterName,
        requesterAddress,
        recipientId: recipientUserId,
        recipientName,
        amount,
        tokenSymbol: currency,
        isFixedAmount,
        memo,
        createdAt: now,
        expiresAt,
        status: "pending" as RequestStatus,
        paymentCount: 0,
        currency,
        requesterPortfolio: portfolio,
      };

      // Create request and send notification in PARALLEL
      const requestRef = db.collection("payment_requests").doc();
      const requestId = requestRef.id;

      await Promise.all([
        // 1. Create the payment request
        requestRef.set(paymentRequest),
        // 2. Add to user's created_requests
        db.collection("users").doc(userId).collection("created_requests").doc(requestId).set({
          requestId,
          createdAt: now,
        }),
        // 3. Add to recipient's received_requests
        db.collection("users").doc(recipientUserId).collection("received_requests").doc(requestId).set({
          requestId,
          status: "pending",
          receivedAt: now,
        }),
      ]);

      logger.info(`✅ Created and sent request ${requestId}: ${amount} ${currency} to ${recipientName}`);

      // Send push notification (don't await - fire and forget)
      sendPaymentRequestNotification(
        recipientUserId,
        requesterName,
        amount,
        currency,
        requestId
      ).catch((err) => logger.warn("Push notification failed:", err));

      return {
        success: true,
        data: {
          requestId,
          recipientUserId,
          recipientName,
          request: {
            ...paymentRequest,
            id: requestId,
            createdAt: paymentRequest.createdAt.toMillis(),
            expiresAt: paymentRequest.expiresAt.toMillis(),
          },
        },
      };
    } catch (error: any) {
      logger.error("❌ Error creating and sending fiat request:", error);
      throw new HttpsError(
        "internal",
        `Failed to create and send request: ${error.message}`
      );
    }
  }
);
