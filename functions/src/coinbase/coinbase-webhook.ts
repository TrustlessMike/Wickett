import { onRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import {
  COINBASE_WEBHOOK_SECRET,
  CoinbaseWebhookPayload,
  CoinbaseWebhookEventType,
  getCoinbaseClient,
} from "./coinbase-client";
import { OnrampSessionStatus } from "./create-onramp-session";
import { OfframpSessionStatus } from "./create-offramp-session";

/**
 * Firebase Cloud Function: Handle Coinbase Webhooks
 *
 * This HTTP endpoint receives webhooks from Coinbase when session status changes.
 * It verifies the webhook signature and updates session status in Firestore.
 *
 * Supported events:
 * - onramp.session.created
 * - onramp.session.pending
 * - onramp.session.completed
 * - onramp.session.failed
 * - offramp.session.created
 * - offramp.session.awaiting_crypto
 * - offramp.session.completed
 * - offramp.session.failed
 *
 * Flow:
 * 1. Verify webhook signature
 * 2. Parse webhook payload
 * 3. Update session status in Firestore
 * 4. Log event for monitoring
 *
 * Configuration:
 * - Add this URL to Coinbase Developer Portal webhook settings
 * - URL: https://<region>-<project-id>.cloudfunctions.net/coinbaseWebhook
 */
export const coinbaseWebhook = onRequest(
  {
    secrets: [COINBASE_WEBHOOK_SECRET],
    cors: false, // Webhooks should only come from Coinbase
  },
  async (req, res) => {
    const db = getFirestore();

    // Only accept POST requests
    if (req.method !== "POST") {
      logger.warn("Invalid webhook request method", { method: req.method });
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      // Get signature from headers
      const signature = req.headers["x-coinbase-signature"] as string;
      if (!signature) {
        logger.warn("Webhook missing signature");
        res.status(401).send("Missing signature");
        return;
      }

      // Get raw body for signature verification
      const rawBody = JSON.stringify(req.body);

      // Verify webhook signature
      const webhookSecret = COINBASE_WEBHOOK_SECRET.value();
      const coinbaseClient = getCoinbaseClient();
      const isValid = coinbaseClient.verifyWebhookSignature(
        rawBody,
        signature,
        webhookSecret
      );

      if (!isValid) {
        logger.error("Invalid webhook signature", {
          signature,
          body: rawBody.substring(0, 100),
        });
        res.status(401).send("Invalid signature");
        return;
      }

      // Parse webhook payload
      const payload = req.body as CoinbaseWebhookPayload;

      logger.info("Received Coinbase webhook", {
        eventType: payload.eventType,
        sessionId: payload.sessionId,
        status: payload.status,
      });

      // Handle different event types
      switch (payload.eventType) {
        case CoinbaseWebhookEventType.ONRAMP_SESSION_CREATED:
        case CoinbaseWebhookEventType.ONRAMP_SESSION_PENDING:
        case CoinbaseWebhookEventType.ONRAMP_SESSION_COMPLETED:
        case CoinbaseWebhookEventType.ONRAMP_SESSION_FAILED:
          await handleOnrampWebhook(db, payload);
          break;

        case CoinbaseWebhookEventType.OFFRAMP_SESSION_CREATED:
        case CoinbaseWebhookEventType.OFFRAMP_SESSION_AWAITING_CRYPTO:
        case CoinbaseWebhookEventType.OFFRAMP_SESSION_COMPLETED:
        case CoinbaseWebhookEventType.OFFRAMP_SESSION_FAILED:
          await handleOfframpWebhook(db, payload);
          break;

        default:
          logger.warn("Unknown webhook event type", {
            eventType: payload.eventType,
          });
      }

      // Always return 200 to acknowledge receipt
      res.status(200).json({ received: true });
    } catch (error: any) {
      logger.error("❌ Failed to process Coinbase webhook", {
        error: error.message,
        stack: error.stack,
      });

      // Return 200 anyway to prevent Coinbase from retrying
      // (we've logged the error for investigation)
      res.status(200).json({ received: true, error: error.message });
    }
  }
);

/**
 * Handle onramp webhook events
 */
async function handleOnrampWebhook(
  db: FirebaseFirestore.Firestore,
  payload: CoinbaseWebhookPayload
) {
  // Find session by coinbaseSessionId
  const sessionsQuery = await db
    .collection("coinbaseOnrampSessions")
    .where("coinbaseSessionId", "==", payload.sessionId)
    .limit(1)
    .get();

  if (sessionsQuery.empty) {
    logger.warn("Onramp session not found for webhook", {
      coinbaseSessionId: payload.sessionId,
    });
    return;
  }

  const sessionDoc = sessionsQuery.docs[0];
  const sessionData = sessionDoc.data();

  // Map Coinbase status to our enum
  let status: OnrampSessionStatus;
  switch (payload.eventType) {
    case CoinbaseWebhookEventType.ONRAMP_SESSION_CREATED:
      status = OnrampSessionStatus.CREATED;
      break;
    case CoinbaseWebhookEventType.ONRAMP_SESSION_PENDING:
      status = OnrampSessionStatus.PENDING;
      break;
    case CoinbaseWebhookEventType.ONRAMP_SESSION_COMPLETED:
      status = OnrampSessionStatus.COMPLETED;
      break;
    case CoinbaseWebhookEventType.ONRAMP_SESSION_FAILED:
      status = OnrampSessionStatus.FAILED;
      break;
    default:
      logger.warn("Unknown onramp event type", {
        eventType: payload.eventType,
      });
      return;
  }

  // Prepare update data
  const updateData: any = {
    status,
    updatedAt: Timestamp.now(),
  };

  if (payload.transactionHash) {
    updateData.transactionHash = payload.transactionHash;
  }

  if (payload.cryptoAmount) {
    updateData.cryptoAmount = payload.cryptoAmount;
  }

  if (status === OnrampSessionStatus.COMPLETED) {
    updateData.completedAt = Timestamp.now();
  }

  if (status === OnrampSessionStatus.FAILED && payload.status) {
    updateData.failureReason = payload.status;
  }

  // Update session
  await sessionDoc.ref.update(updateData);

  logger.info("✅ Onramp session updated", {
    sessionId: sessionDoc.id,
    coinbaseSessionId: payload.sessionId,
    status,
    userId: sessionData.userId,
  });

  // If completed, trigger balance refresh notification
  // TODO: Send push notification to user
  if (status === OnrampSessionStatus.COMPLETED) {
    logger.info("🎉 Onramp completed", {
      userId: sessionData.userId,
      amount: payload.cryptoAmount,
      asset: payload.assetSymbol,
      transactionHash: payload.transactionHash,
    });
  }
}

/**
 * Handle offramp webhook events
 */
async function handleOfframpWebhook(
  db: FirebaseFirestore.Firestore,
  payload: CoinbaseWebhookPayload
) {
  // Find session by coinbaseSessionId
  const sessionsQuery = await db
    .collection("coinbaseOfframpSessions")
    .where("coinbaseSessionId", "==", payload.sessionId)
    .limit(1)
    .get();

  if (sessionsQuery.empty) {
    logger.warn("Offramp session not found for webhook", {
      coinbaseSessionId: payload.sessionId,
    });
    return;
  }

  const sessionDoc = sessionsQuery.docs[0];
  const sessionData = sessionDoc.data();

  // Map Coinbase status to our enum
  let status: OfframpSessionStatus;
  switch (payload.eventType) {
    case CoinbaseWebhookEventType.OFFRAMP_SESSION_CREATED:
      status = OfframpSessionStatus.CREATED;
      break;
    case CoinbaseWebhookEventType.OFFRAMP_SESSION_AWAITING_CRYPTO:
      status = OfframpSessionStatus.AWAITING_CRYPTO;
      break;
    case CoinbaseWebhookEventType.OFFRAMP_SESSION_COMPLETED:
      status = OfframpSessionStatus.COMPLETED;
      break;
    case CoinbaseWebhookEventType.OFFRAMP_SESSION_FAILED:
      status = OfframpSessionStatus.FAILED;
      break;
    default:
      logger.warn("Unknown offramp event type", {
        eventType: payload.eventType,
      });
      return;
  }

  // Prepare update data
  const updateData: any = {
    status,
    updatedAt: Timestamp.now(),
  };

  if (payload.transactionHash) {
    updateData.transactionHash = payload.transactionHash;
  }

  if (payload.cryptoAmount) {
    updateData.cryptoAmount = payload.cryptoAmount;
  }

  if (status === OfframpSessionStatus.COMPLETED) {
    updateData.completedAt = Timestamp.now();
  }

  if (status === OfframpSessionStatus.FAILED && payload.status) {
    updateData.failureReason = payload.status;
  }

  // Update session
  await sessionDoc.ref.update(updateData);

  logger.info("✅ Offramp session updated", {
    sessionId: sessionDoc.id,
    coinbaseSessionId: payload.sessionId,
    status,
    userId: sessionData.userId,
  });

  // If completed, send notification
  // TODO: Send push notification to user
  if (status === OfframpSessionStatus.COMPLETED) {
    logger.info("🎉 Offramp completed", {
      userId: sessionData.userId,
      fiatAmount: sessionData.fiatAmount,
      fiatCurrency: sessionData.fiatCurrency,
      transactionHash: payload.transactionHash,
    });
  }
}
