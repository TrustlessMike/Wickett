import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore } from "firebase-admin/firestore";
import { getCoinbaseClient, COINBASE_API_KEY, COINBASE_PROJECT_ID } from "./coinbase-client";

/**
 * Request body for getting transfer status
 */
interface GetTransferStatusRequest {
  sessionId: string;
  sessionType: "onramp" | "offramp";
}

/**
 * Response for transfer status
 */
interface GetTransferStatusResponse {
  sessionId: string;
  coinbaseSessionId: string;
  status: string;
  walletAddress?: string;
  depositAddress?: string;
  assetSymbol: string;
  fiatAmount?: number;
  cryptoAmount?: number;
  transactionHash?: string;
  createdAt: string;
  updatedAt: string;
  completedAt?: string;
  failureReason?: string;
}

/**
 * Firebase Cloud Function: Get Coinbase Transfer Status
 *
 * This function allows the iOS app to poll the status of an onramp or offramp session.
 * It fetches the latest status from Firestore and optionally from Coinbase API.
 *
 * Usage:
 * - Call after creating a session to monitor progress
 * - Poll every 5-10 seconds while session is pending
 * - Stop polling when status is "completed" or "failed"
 *
 * @param request - Contains sessionId and sessionType
 * @param context - Firebase auth context
 * @returns Current session status and details
 */
export const getCoinbaseTransferStatus = onCall(
  {
    secrets: [COINBASE_API_KEY, COINBASE_PROJECT_ID],
    enforceAppCheck: false, // TODO: Enable in production
    cors: true,
  },
  async (request) => {
    const db = getFirestore();
    const userId = request.auth?.uid;

    // Validate authentication
    if (!userId) {
      logger.warn("Unauthenticated transfer status request");
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const data = request.data as GetTransferStatusRequest;

    // Validate required fields
    if (!data.sessionId) {
      throw new HttpsError("invalid-argument", "Session ID is required");
    }

    if (!data.sessionType || !["onramp", "offramp"].includes(data.sessionType)) {
      throw new HttpsError("invalid-argument", "Valid session type is required (onramp or offramp)");
    }

    logger.info("Fetching Coinbase transfer status", {
      userId,
      sessionId: data.sessionId,
      sessionType: data.sessionType,
    });

    try {
      // Determine collection based on session type
      const collectionName =
        data.sessionType === "onramp"
          ? "coinbaseOnrampSessions"
          : "coinbaseOfframpSessions";

      // Fetch session from Firestore
      const sessionDoc = await db.collection(collectionName).doc(data.sessionId).get();

      if (!sessionDoc.exists) {
        logger.warn("Session not found", {
          sessionId: data.sessionId,
          sessionType: data.sessionType,
        });
        throw new HttpsError("not-found", "Session not found");
      }

      const sessionData = sessionDoc.data()!;

      // Verify user owns this session
      if (sessionData.userId !== userId) {
        logger.warn("Unauthorized session access attempt", {
          userId,
          sessionOwnerId: sessionData.userId,
          sessionId: data.sessionId,
        });
        throw new HttpsError("permission-denied", "Access denied");
      }

      // If session is still pending, optionally fetch latest status from Coinbase
      const isPending = ["created", "pending", "awaiting_crypto", "processing"].includes(
        sessionData.status
      );

      if (isPending) {
        try {
          const coinbaseClient = getCoinbaseClient();
          const latestStatus = await coinbaseClient.getSessionStatus(
            sessionData.coinbaseSessionId
          );

          // Update Firestore if status changed
          if (latestStatus.status !== sessionData.status) {
            logger.info("Updating session with latest Coinbase status", {
              sessionId: data.sessionId,
              oldStatus: sessionData.status,
              newStatus: latestStatus.status,
            });

            const updateData: any = {
              status: latestStatus.status,
              updatedAt: new Date(),
            };

            if (latestStatus.transactionHash) {
              updateData.transactionHash = latestStatus.transactionHash;
            }

            if (latestStatus.cryptoAmount) {
              updateData.cryptoAmount = latestStatus.cryptoAmount;
            }

            if (["completed", "failed"].includes(latestStatus.status)) {
              updateData.completedAt = new Date();
            }

            await sessionDoc.ref.update(updateData);

            // Update local data for response
            Object.assign(sessionData, updateData);
          }
        } catch (statusError) {
          logger.warn("Failed to fetch latest status from Coinbase API", {
            sessionId: data.sessionId,
            error: statusError,
          });
          // Continue with Firestore data
        }
      }

      logger.info("✅ Transfer status retrieved", {
        sessionId: data.sessionId,
        status: sessionData.status,
        userId,
      });

      // Build response
      const response: GetTransferStatusResponse = {
        sessionId: data.sessionId,
        coinbaseSessionId: sessionData.coinbaseSessionId,
        status: sessionData.status,
        assetSymbol: sessionData.assetSymbol,
        fiatAmount: sessionData.fiatAmount,
        cryptoAmount: sessionData.cryptoAmount,
        transactionHash: sessionData.transactionHash,
        createdAt: sessionData.createdAt?.toDate?.()?.toISOString() || sessionData.createdAt,
        updatedAt: sessionData.updatedAt?.toDate?.()?.toISOString() || sessionData.updatedAt,
        completedAt: sessionData.completedAt?.toDate?.()?.toISOString(),
        failureReason: sessionData.failureReason,
      };

      // Add type-specific fields
      if (data.sessionType === "onramp") {
        response.walletAddress = sessionData.walletAddress;
      } else {
        response.depositAddress = sessionData.depositAddress;
      }

      return response;
    } catch (error: any) {
      // If it's already an HttpsError, rethrow it
      if (error.code) {
        throw error;
      }

      logger.error("❌ Failed to get transfer status", {
        userId,
        sessionId: data.sessionId,
        error: error.message,
        stack: error.stack,
      });

      throw new HttpsError("internal", "Failed to get transfer status");
    }
  }
);
