import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import {
  CreateRequestData,
  PaymentRequest,
  RequestStatus,
} from "./types";

/**
 * Cloud Function: createPaymentRequest
 * Creates a new payment request and stores it in Firestore
 */
export const createPaymentRequest = onCall(
  {
    invoker: "public", // Allow authenticated Firebase users to invoke
  },
  async (request) => {
  const { auth, data } = request;

  // Verify authentication
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const userId = auth.uid;
  const { amount, tokenSymbol, isFixedAmount, memo } = data as CreateRequestData;

  // Validate input
  if (!amount || amount <= 0) {
    throw new HttpsError("invalid-argument", "Amount must be greater than 0");
  }

  if (!tokenSymbol || typeof tokenSymbol !== "string") {
    throw new HttpsError("invalid-argument", "Token symbol is required");
  }

  if (typeof isFixedAmount !== "boolean") {
    throw new HttpsError("invalid-argument", "isFixedAmount must be a boolean");
  }

  if (!memo || typeof memo !== "string") {
    throw new HttpsError("invalid-argument", "Memo is required");
  }

  try {
    const db = getFirestore();

    // Get user info
    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found");
    }

    const userData = userDoc.data()!;
    const requesterName = userData.displayName || "Unknown";
    const requesterAddress = userData.walletAddress;

    if (!requesterAddress) {
      throw new HttpsError("failed-precondition", "User does not have a wallet address");
    }

    // Create payment request
    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(now.toMillis() + 7 * 24 * 60 * 60 * 1000); // 7 days

    const paymentRequest: PaymentRequest = {
      requesterId: userId,
      requesterName,
      requesterAddress,
      amount,
      tokenSymbol,
      isFixedAmount,
      memo,
      createdAt: now,
      expiresAt,
      status: "pending" as RequestStatus,
      paymentCount: 0,
    };

    // Add token mint for SPL tokens if needed
    // This would be looked up from TokenRegistry on frontend
    // For now, we'll add it in the fulfill step

    // Store in payment_requests collection
    const requestRef = await db.collection("payment_requests").add(paymentRequest);
    const requestId = requestRef.id;

    // Add to user's created_requests subcollection
    await db
      .collection("users")
      .doc(userId)
      .collection("created_requests")
      .doc(requestId)
      .set({
        requestId,
        createdAt: now,
      });

    logger.info(`✅ Payment request created: ${requestId} by ${userId}`);

    return {
      success: true,
      data: {
        requestId,
        request: {
          ...paymentRequest,
          id: requestId,
          createdAt: paymentRequest.createdAt.toMillis(),
          expiresAt: paymentRequest.expiresAt.toMillis(),
        },
      },
    };
  } catch (error: any) {
    logger.error("❌ Error creating payment request:", error);
    throw new HttpsError(
      "internal",
      `Failed to create payment request: ${error.message}`
    );
  }
});
