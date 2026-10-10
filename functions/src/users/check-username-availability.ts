import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

/**
 * Cloud Function: checkUsernameAvailability
 * Checks if a username is available for registration
 * Usernames are unique across the platform
 */
export const checkUsernameAvailability = onCall(
  {
    invoker: "public",
  },
  async (request) => {
    const { data } = request;
    const { username } = data as { username: string };

    // Validate input
    if (!username || typeof username !== "string") {
      throw new HttpsError("invalid-argument", "Username is required");
    }

    // Normalize username (lowercase, trim)
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
      return {
        available: false,
        reason: "This username is reserved",
      };
    }

    try {
      const db = getFirestore();

      // Check if username already exists
      const usernameQuery = await db
        .collection("users")
        .where("username", "==", normalizedUsername)
        .limit(1)
        .get();

      if (!usernameQuery.empty) {
        logger.info(`Username ${normalizedUsername} is taken`);
        return {
          available: false,
          reason: "This username is already taken",
        };
      }

      logger.info(`Username ${normalizedUsername} is available`);
      return {
        available: true,
        username: normalizedUsername,
      };
    } catch (error: any) {
      logger.error("Error checking username availability:", error);
      throw new HttpsError(
        "internal",
        `Failed to check username availability: ${error.message}`
      );
    }
  }
);
