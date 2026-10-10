import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: updateUsername
 * Sets or updates a user's username
 * Enforces uniqueness and validation rules
 */
export const updateUsername = onCall(
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
    const { username } = data as { username: string };

    // Validate input
    if (!username || typeof username !== "string") {
      throw new HttpsError("invalid-argument", "Username is required");
    }

    // Normalize username
    const normalizedUsername = username.toLowerCase().trim();

    // Validate username format
    const usernameRegex = /^[a-z0-9_-]{3,20}$/;
    if (!usernameRegex.test(normalizedUsername)) {
      throw new HttpsError(
        "invalid-argument",
        "Username must be 3-20 characters and contain only lowercase letters, numbers, hyphens, or underscores"
      );
    }

    // Check for reserved usernames
    const reservedUsernames = [
      "admin",
      "wickett",
      "support",
      "help",
      "api",
      "system",
      "official",
      "staff",
      "moderator",
      "root",
      "null",
      "undefined",
    ];

    if (reservedUsernames.includes(normalizedUsername)) {
      throw new HttpsError("invalid-argument", "This username is reserved");
    }

    try {
      const db = getFirestore();

      // Get current user document to check existing username and cooldown
      const userDoc = await db.collection("users").doc(userId).get();
      const userData = userDoc.data();

      // Check if user already has a username set
      if (userData?.username) {
        // If trying to set the same username, it's a no-op
        if (userData.username === normalizedUsername) {
          logger.info(`User ${userId} already has username ${normalizedUsername}`);
          return {
            success: true,
            data: {
              username: normalizedUsername,
            },
          };
        }

        // Check 90-day cooldown
        const lastUsernameChangedAt = userData.lastUsernameChangedAt?.toDate?.();
        if (lastUsernameChangedAt) {
          const cooldownMs = 90 * 24 * 60 * 60 * 1000; // 90 days in milliseconds
          const timeSinceLastChange = Date.now() - lastUsernameChangedAt.getTime();

          if (timeSinceLastChange < cooldownMs) {
            const daysRemaining = Math.ceil((cooldownMs - timeSinceLastChange) / (24 * 60 * 60 * 1000));
            throw new HttpsError(
              "failed-precondition",
              `You can only change your username once every 90 days. ${daysRemaining} days remaining.`
            );
          }
        } else {
          // First time changing username (had one set during onboarding) - set the cooldown now
          // This allows the initial username to be changed once, then enforces 90-day cooldown
        }
      }

      // Check if username is already taken by another user
      const usernameQuery = await db
        .collection("users")
        .where("username", "==", normalizedUsername)
        .limit(1)
        .get();

      if (!usernameQuery.empty) {
        const existingUser = usernameQuery.docs[0];
        // If it's taken by a different user, reject
        if (existingUser.id !== userId) {
          throw new HttpsError(
            "already-exists",
            "This username is already taken"
          );
        }
      }

      // Update user document with username and cooldown timestamp
      await db
        .collection("users")
        .doc(userId)
        .update({
          username: normalizedUsername,
          lastUsernameChangedAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });

      logger.info(`✅ Username set for user ${userId}: ${normalizedUsername}`);

      return {
        success: true,
        data: {
          username: normalizedUsername,
        },
      };
    } catch (error: any) {
      logger.error("❌ Error updating username:", error);

      // Re-throw HttpsErrors as-is
      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError(
        "internal",
        `Failed to update username: ${error.message}`
      );
    }
  }
);
