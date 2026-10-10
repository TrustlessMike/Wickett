import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: getPaymentRequest
 * Retrieves a payment request by ID (for deep links and QR codes)
 */
export const getPaymentRequest = onCall(
  {
    invoker: "public",
  },
  async (request) => {
  const { auth, data } = request;

  // Verify authentication
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const { requestId } = data as { requestId: string };

  // Validate input
  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "Request ID is required");
  }

  try {
    const db = getFirestore();

    // Get payment request
    const requestDoc = await db.collection("payment_requests").doc(requestId).get();

    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "Payment request not found");
    }

    const requestData = requestDoc.data()!;

    // Check if expired
    const now = Date.now();
    const expiresAt = requestData.expiresAt.toMillis();
    const isExpired = now > expiresAt;

    // Update status to expired if needed
    if (isExpired && requestData.status === "pending") {
      await requestDoc.ref.update({ status: "expired" });
      requestData.status = "expired";
    }

    logger.info(`📥 Payment request fetched: ${requestId}`);

    return {
      success: true,
      data: {
        id: requestId,
        ...requestData,
        createdAt: requestData.createdAt.toMillis(),
        expiresAt: requestData.expiresAt.toMillis(),
        lastPaidAt: requestData.lastPaidAt?.toMillis(),
        isExpired,
      },
    };
  } catch (error: any) {
    logger.error("❌ Error fetching payment request:", error);
    throw new HttpsError(
      "internal",
      `Failed to fetch payment request: ${error.message}`
    );
  }
});
