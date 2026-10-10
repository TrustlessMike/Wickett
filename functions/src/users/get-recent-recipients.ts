import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import { getRecentRecipients as fetchRecentRecipients } from "../middleware/recipients-tracker";

interface GetRecentRecipientsRequest {
  limit?: number;
}

interface RecentRecipientResponse {
  id: string;
  address: string;
  displayName?: string;
  lastSentAt: string; // ISO date string
  tokenType?: string;
  frequency: number;
}

/**
 * Get recent recipients for the authenticated user
 * Cloud Function: getRecentRecipients
 */
export const getRecentRecipients = onCall<GetRecentRecipientsRequest>(
  async (request) => {
    const { data, auth } = request;

    // Verify authentication
    if (!auth) {
      logger.warn("Unauthenticated request to getRecentRecipients");
      throw new HttpsError(
        "unauthenticated",
        "User must be authenticated to get recent recipients"
      );
    }

    const userId = auth.uid;
    const limit = data.limit || 10;

    logger.info(
      `Getting recent recipients for user: ${userId}, limit: ${limit}`
    );

    try {
      // Fetch recent recipients from Firestore
      const recipients = await fetchRecentRecipients(userId, limit);

      // Use cached displayName from recipients (populated when saved)
      // Only lookup names for recipients that don't have one cached
      const recipientsNeedingLookup = recipients.filter(r => !r.displayName);
      const lookupMap = new Map<string, string>();

      // Batch lookup for any missing display names (should be rare after fix)
      if (recipientsNeedingLookup.length > 0) {
        const addresses = recipientsNeedingLookup.map(r => r.address);
        // Firestore 'in' query supports up to 30 values
        const chunks = [];
        for (let i = 0; i < addresses.length; i += 30) {
          chunks.push(addresses.slice(i, i + 30));
        }

        for (const chunk of chunks) {
          try {
            const usersSnapshot = await admin
              .firestore()
              .collection("users")
              .where("walletAddress", "in", chunk)
              .get();

            usersSnapshot.docs.forEach(doc => {
              const data = doc.data();
              if (data.walletAddress && data.displayName) {
                lookupMap.set(data.walletAddress, data.displayName);
              }
            });
          } catch (error) {
            logger.warn("Batch display name lookup failed:", error);
          }
        }
      }

      // Build response using cached displayName or fallback to lookup
      const enrichedRecipients: RecentRecipientResponse[] = recipients.map(recipient => ({
        id: recipient.id,
        address: recipient.address,
        displayName: recipient.displayName || lookupMap.get(recipient.address),
        lastSentAt: recipient.lastSentAt.toDate().toISOString(),
        tokenType: recipient.tokenType,
        frequency: recipient.frequency,
      }));

      logger.info(
        `✅ Successfully retrieved ${enrichedRecipients.length} recent recipients`
      );

      return {
        recipients: enrichedRecipients,
      };
    } catch (error: any) {
      logger.error("Failed to get recent recipients:", error);
      throw new HttpsError(
        "internal",
        `Failed to retrieve recent recipients: ${error.message}`
      );
    }
  }
);
