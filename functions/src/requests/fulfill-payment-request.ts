import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { FulfillRequestData } from "./types";
import { VersionedTransaction } from "@solana/web3.js";
import { sendAndConfirmTransactionWithRetry } from "../solana/transaction-builder";
import { saveRecentRecipient } from "../middleware/recipients-tracker";

/**
 * Cloud Function: fulfillPaymentRequest
 * Process payment for a request (broadcasts pre-signed transaction)
 * Similar to broadcastSignedTransaction but also updates request status
 */
export const fulfillPaymentRequest = onCall(
  {
    invoker: "public",
  },
  async (request) => {
  const { auth, data } = request;

  // Verify authentication
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const payerId = auth.uid;
  const { requestId, amount, signedTransaction } = data as FulfillRequestData;

  // Validate input
  if (!requestId || typeof requestId !== "string") {
    throw new HttpsError("invalid-argument", "Request ID is required");
  }

  if (!signedTransaction || typeof signedTransaction !== "string") {
    throw new HttpsError("invalid-argument", "Signed transaction is required");
  }

  try {
    const db = getFirestore();

    // Get payment request
    const requestDoc = await db.collection("payment_requests").doc(requestId).get();

    if (!requestDoc.exists) {
      throw new HttpsError("not-found", "Payment request not found");
    }

    const requestData = requestDoc.data()!;

    // Validate request status
    if (requestData.status !== "pending") {
      throw new HttpsError("failed-precondition", "Request is not active");
    }

    // Check if expired
    const now = Date.now();
    const expiresAt = requestData.expiresAt.toMillis();

    if (now > expiresAt) {
      // Mark as expired
      await requestDoc.ref.update({ status: "expired" });
      throw new HttpsError("failed-precondition", "Request has expired");
    }

    // Validate amount for flexible requests
    if (!requestData.isFixedAmount) {
      if (!amount || amount <= 0) {
        throw new HttpsError(
          "invalid-argument",
          "Amount is required for flexible payment requests"
        );
      }
    } else {
      // For fixed amounts, ensure amount matches (or use request amount)
      const paymentAmount = amount || requestData.amount;
      if (Math.abs(paymentAmount - requestData.amount) > 0.0001) {
        throw new HttpsError(
          "invalid-argument",
          `Amount must be exactly ${requestData.amount}`
        );
      }
    }

    // Deserialize and broadcast transaction
    const transactionBuffer = Buffer.from(signedTransaction, "base64");
    const transaction = VersionedTransaction.deserialize(transactionBuffer);

    logger.info(`📡 Broadcasting payment for request ${requestId}...`);

    // Send and confirm transaction
    const signature = await sendAndConfirmTransactionWithRetry(transaction, {
      maxRetries: 3,
    });

    logger.info(`✅ Transaction confirmed: ${signature}`);

    // Update request status (reusable, so keep as pending but increment count)
    await requestDoc.ref.update({
      paymentCount: FieldValue.increment(1),
      lastPaidAt: Timestamp.now(),
    });

    // Update payer's received_requests if they have this in their inbox
    const receivedRequestRef = db
      .collection("users")
      .doc(payerId)
      .collection("received_requests")
      .doc(requestId);

    const receivedRequestDoc = await receivedRequestRef.get();
    if (receivedRequestDoc.exists) {
      await receivedRequestRef.update({
        status: "paid",
        paidAt: Timestamp.now(),
      });
    }

    // Update recent recipients for the payer
    await saveRecentRecipient(
      payerId,
      requestData.requesterAddress,
      requestData.tokenSymbol
    );

    // TODO: Send push notification to requester
    logger.info(
      `✅ Payment request ${requestId} fulfilled by ${payerId}. Signature: ${signature}`
    );

    const explorerUrl = `https://solscan.io/tx/${signature}?cluster=mainnet`;

    return {
      success: true,
      data: {
        transactionHash: signature,
        explorerUrl,
        requestId,
        paymentCount: requestData.paymentCount + 1,
      },
    };
  } catch (error: any) {
    logger.error("❌ Error fulfilling payment request:", error);
    throw new HttpsError(
      "internal",
      `Failed to fulfill payment request: ${error.message}`
    );
  }
});
