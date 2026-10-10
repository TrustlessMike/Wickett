import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: getMyRequests
 * Get all payment requests created by the current user
 */
export const getMyRequests = onCall(
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

    // Get user's created_requests
    const createdRequestsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("created_requests")
      .orderBy("createdAt", "desc")
      .limit(limit)
      .get();

    const requestIds = createdRequestsSnapshot.docs.map((doc) => doc.data().requestId);

    if (requestIds.length === 0) {
      return {
        success: true,
        data: {
          requests: [],
          count: 0,
        },
      };
    }

    // Fetch full request details
    const requests = [];
    const now = Date.now();

    for (const requestId of requestIds) {
      const requestDoc = await db
        .collection("payment_requests")
        .doc(requestId)
        .get();

      if (requestDoc.exists) {
        const requestData = requestDoc.data()!;

        // Check if expired
        const expiresAt = requestData.expiresAt.toMillis();
        const isExpired = now > expiresAt;

        // Update status to expired if needed
        if (isExpired && requestData.status === "pending") {
          await requestDoc.ref.update({ status: "expired" });
          requestData.status = "expired";
        }

        // Filter by status if specified
        if (status && requestData.status !== status) {
          continue;
        }

        requests.push({
          id: requestId,
          ...requestData,
          createdAt: requestData.createdAt.toMillis(),
          expiresAt: requestData.expiresAt.toMillis(),
          lastPaidAt: requestData.lastPaidAt?.toMillis(),
          isExpired,
        });
      }
    }

    logger.info(`📋 Fetched ${requests.length} requests for user ${userId}`);

    return {
      success: true,
      data: {
        requests,
        count: requests.length,
      },
    };
  } catch (error: any) {
    logger.error("❌ Error fetching user's requests:", error);
    throw new HttpsError(
      "internal",
      `Failed to fetch requests: ${error.message}`
    );
  }
});
