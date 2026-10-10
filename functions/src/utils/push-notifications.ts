import * as admin from "firebase-admin";
import { logger } from "firebase-functions/v2";

interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

/**
 * Send push notification to a user by their userId
 */
export async function sendPushNotification(
  userId: string,
  payload: NotificationPayload
): Promise<boolean> {
  try {
    const db = admin.firestore();
    const userDoc = await db.collection("users").doc(userId).get();

    if (!userDoc.exists) {
      logger.warn(`⚠️ User not found for push notification: ${userId}`);
      return false;
    }

    const userData = userDoc.data();
    const fcmToken = userData?.fcmToken;

    if (!fcmToken) {
      logger.warn(`⚠️ No FCM token for user: ${userId}`);
      return false;
    }

    const message: admin.messaging.Message = {
      token: fcmToken,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      data: payload.data,
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    logger.info(`✅ Push notification sent: ${response}`);
    return true;
  } catch (error: any) {
    // Handle invalid token error - remove stale token
    if (
      error.code === "messaging/invalid-registration-token" ||
      error.code === "messaging/registration-token-not-registered"
    ) {
      logger.warn(`⚠️ Invalid FCM token for user ${userId}, removing...`);
      try {
        await admin.firestore().collection("users").doc(userId).update({
          fcmToken: admin.firestore.FieldValue.delete(),
        });
      } catch (deleteError) {
        logger.error("Failed to delete invalid token:", deleteError);
      }
    } else {
      logger.error(`❌ Failed to send push notification: ${error.message}`);
    }
    return false;
  }
}

/**
 * Send payment request notification
 */
export async function sendPaymentRequestNotification(
  recipientUserId: string,
  requesterName: string,
  amount: number,
  currency: string,
  requestId: string
): Promise<boolean> {
  const formattedAmount = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency === "USD" ? "USD" : "USD",
  }).format(amount);

  return sendPushNotification(recipientUserId, {
    title: "Payment Request",
    body: `${requesterName} requested ${formattedAmount}`,
    data: {
      type: "payment_request",
      requestId: requestId,
      amount: amount.toString(),
      currency: currency,
    },
  });
}

/**
 * Send payment received notification
 */
export async function sendPaymentReceivedNotification(
  recipientUserId: string,
  senderName: string,
  amount: number,
  currency: string
): Promise<boolean> {
  const formattedAmount = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency === "USD" ? "USD" : "USD",
  }).format(amount);

  return sendPushNotification(recipientUserId, {
    title: "Payment Received",
    body: `${senderName} sent you ${formattedAmount}`,
    data: {
      type: "payment_received",
      amount: amount.toString(),
      currency: currency,
    },
  });
}
