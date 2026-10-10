import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { RejectRequestData } from "./types";

/**
 * Cloud Function: rejectPaymentRequest
 * Reject a payment request with optional message
 */
export const rejectPaymentRequest = onCall(
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
  const { requestId, message } = data as RejectRequestData;

  // Validate input
  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "Request ID is required");
  }

  try {
    const db = getFirestore();

    // Get payment request to verify it exists
    const requestDoc = await db.collection("payment_requests").doc(requestId).get();

    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "Payment request not found");
    }

    const requestData = requestDoc.data()!;

    // Check if request is still active
    if (requestData.status !== "pending") {
      throw new HttpsError("failed-precondition", "Request is not active");
    }

    // Update user's received_requests status
    const receivedRequestRef = db
      .collection("users")
      .doc(userId)
      .collection("received_requests")
      .doc(requestId);

    const receivedRequestDoc = await receivedRequestRef.get();

    if (!receivedRequestDoc.exists) {
      throw new HttpsError(
        "not-found",
        "You don't have this request in your inbox"
      );
    }

    // Update to rejected status with optional message
    await receivedRequestRef.update({
      status: "rejected",
      rejectionMessage: message || "",
      rejectedAt: Timestamp.now(),
    });

    // TODO: Send push notification to requester about rejection
    logger.info(
      `❌ Payment request ${requestId} rejected by ${userId}${
        message ? ` with message: "${message}"` : ""
      }`
    );

    return {
      success: true,
      data: {
        requestId,
        message: "Request rejected successfully",
      },
    };
  } catch (error: any) {
    logger.error("❌ Error rejecting payment request:", error);
    throw new HttpsError(
      "internal",
      `Failed to reject payment request: ${error.message}`
    );
  }
});
