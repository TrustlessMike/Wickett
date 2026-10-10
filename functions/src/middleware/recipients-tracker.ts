import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

export interface RecentRecipient {
  id: string;
  address: string;
  lastSentAt: admin.firestore.Timestamp;
  tokenType?: string; // "SOL" or token mint address
  frequency: number; // Number of times sent to this address
  displayName?: string; // Cached display name for fast lookups
}

/**
 * Save or update a recent recipient for a user
 */
export async function saveRecentRecipient(
  userId: string,
  recipientAddress: string,
  tokenType?: string
): Promise<void> {
  try {
    const db = admin.firestore();
    const recipientsRef = db
      .collection("users")
      .doc(userId)
      .collection("recent_recipients");

    // Lookup display name for recipient (do this once when saving, not on every fetch)
    let displayName: string | undefined;
    try {
      const userSnapshot = await db
        .collection("users")
        .where("walletAddress", "==", recipientAddress)
        .limit(1)
        .get();

      if (!userSnapshot.empty) {
        displayName = userSnapshot.docs[0].data().displayName;
      }
    } catch (error) {
      logger.warn(`Failed to lookup display name for ${recipientAddress}`);
    }

    // Check if recipient already exists
    const existingQuery = await recipientsRef
      .where("address", "==", recipientAddress)
      .limit(1)
      .get();

    if (!existingQuery.empty) {
      // Update existing recipient
      const existingDoc = existingQuery.docs[0];
      const existingData = existingDoc.data() as RecentRecipient;

      const updateData: Record<string, any> = {
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        frequency: (existingData.frequency || 0) + 1,
        tokenType: tokenType || existingData.tokenType,
      };

      // Update displayName if we found one (or if it changed)
      if (displayName) {
        updateData.displayName = displayName;
      }

      await existingDoc.ref.update(updateData);

      logger.info(`Updated recent recipient: ${recipientAddress}`);
    } else {
      // Create new recipient with cached displayName
      await recipientsRef.add({
        address: recipientAddress,
        lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
        tokenType: tokenType || "SOL",
        frequency: 1,
        displayName: displayName || undefined,
      });

      logger.info(`Added new recent recipient: ${recipientAddress}${displayName ? ` (${displayName})` : ""}`);
    }

    // Clean up old recipients (keep only last 50)
    const allRecipients = await recipientsRef
      .orderBy("lastSentAt", "desc")
      .get();

    if (allRecipients.size > 50) {
      const toDelete = allRecipients.docs.slice(50);
      const batch = db.batch();

      toDelete.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();
      logger.info(`Cleaned up ${toDelete.length} old recipients`);
    }
  } catch (error) {
    logger.error("Failed to save recent recipient:", error);
    // Don't throw - this is a non-critical operation
  }
}

/**
 * Get recent recipients for a user
 */
export async function getRecentRecipients(
  userId: string,
  limit: number = 10
): Promise<RecentRecipient[]> {
  try {
    const db = admin.firestore();
    const snapshot = await db
      .collection("users")
      .doc(userId)
      .collection("recent_recipients")
      .orderBy("lastSentAt", "desc")
      .limit(limit)
      .get();

    return snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    })) as RecentRecipient[];
  } catch (error) {
    logger.error("Failed to get recent recipients:", error);
    return [];
  }
}
