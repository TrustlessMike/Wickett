import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: getReceivedRequests
 * Get all payment requests received by the current user (requests to pay)
 */
export const getReceivedRequests = onCall(
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
  const { limit = 50, status } = data as { limit?: number; status?: string };

  try {
    const db = getFirestore();

    // Get user's received_requests
    const receivedRequestsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("received_requests")
      .orderBy("receivedAt", "desc")
      .limit(limit)
      .get();

    const requests = [];
    const now = Date.now();

    for (const doc of receivedRequestsSnapshot.docs) {
      const receivedData = doc.data();
      const requestId = receivedData.requestId;

      // Fetch full request details
      const requestDoc = await db
        .collection("payment_requests")
        .doc(requestId)
        .get();

      if (requestDoc.exists) {
        const requestData = requestDoc.data()!;

        // Check if expired
        const expiresAt = requestData.expiresAt.toMillis();
        const isExpired = now > expiresAt;

        // Update main request status to expired if needed
        if (isExpired && requestData.status === "pending") {
          await requestDoc.ref.update({ status: "expired" });
          requestData.status = "expired";
        }

        // Filter by received request status if specified
        if (status && receivedData.status !== status) {
          continue;
        }

        requests.push({
          id: requestId,
          request: {
            ...requestData,
            createdAt: requestData.createdAt.toMillis(),
            expiresAt: requestData.expiresAt.toMillis(),
            lastPaidAt: requestData.lastPaidAt?.toMillis(),
            isExpired,
          },
          receivedAt: receivedData.receivedAt?.toMillis(),
          viewedAt: receivedData.viewedAt?.toMillis(),
          status: receivedData.status,
          rejectionMessage: receivedData.rejectionMessage,
          paidAt: receivedData.paidAt?.toMillis(),
          rejectedAt: receivedData.rejectedAt?.toMillis(),
        });
      }
    }

    logger.info(`📬 Fetched ${requests.length} received requests for user ${userId}`);

    return {
      success: true,
      data: {
        requests,
        count: requests.length,
      },
    };
  } catch (error: any) {
    logger.error("❌ Error fetching received requests:", error);
    throw new HttpsError(
      "internal",
      `Failed to fetch received requests: ${error.message}`
    );
  }
});
