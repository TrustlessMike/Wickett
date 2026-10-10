import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Create Firebase custom token for Privy authenticated users
 * This bridges Privy authentication with Firebase for backend compatibility
 */
export const createFirebaseCustomToken = onCall(
  {
    // Allow unauthenticated calls since users aren't signed in to Firebase yet
    enforceAppCheck: false,
    invoker: "public",
  },
  async (request) => {
    try {
      const { privyUserId, privyUserData, authMethod, timestamp } = request.data;

      if (!privyUserId) {
        throw new HttpsError("invalid-argument", "Privy user ID is required");
      }

      logger.info(`Creating Firebase custom token for Privy user: ${privyUserId}`);
      logger.info(`Auth method: ${authMethod || "unknown"}`);

      // Create custom claims for Firebase
      const customClaims = {
        privyUserId: privyUserId,
        authProvider: "privy",
        authMethod: authMethod || "privy",
        walletAddress: privyUserData?.wallet?.address || null,
        email: privyUserData?.email || null,
        displayName: privyUserData?.displayName || null,
        timestamp: timestamp || Date.now(),
      };

      // Create Firebase custom token
      // Use Privy user ID as Firebase UID for consistency
      // Handle cases where privyUserId already has "privy_" prefix
      const firebaseUid = privyUserId.startsWith("privy_")
        ? privyUserId
        : `privy_${privyUserId}`;

      // Create custom token with extended session duration
      // Note: Custom tokens themselves don't expire, but the ID tokens created
      // from them will follow the client's session configuration
      const customToken = await admin.auth().createCustomToken(
        firebaseUid,
        customClaims
      );

      logger.info(`Custom token created successfully for: ${firebaseUid}`);

      // Update user document in Firestore with latest data
      const db = admin.firestore();

      // Build user data object, only including displayName/walletAddress if Privy has values
      // (we don't want to overwrite these fields if they're already set)
      const userData: any = {
        privyUserId: privyUserId,
        email: privyUserData?.email || null,
        authProvider: "privy",
        authMethod: authMethod || "privy",
        lastSignIn: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // Only update displayName if Privy provides one (don't overwrite with null)
      if (privyUserData?.displayName) {
        userData.displayName = privyUserData.displayName;
      }

      // Only update walletAddress if Privy provides one (don't overwrite with null)
      if (privyUserData?.wallet?.address) {
        userData.walletAddress = privyUserData.wallet.address;
      }

      await db.collection("users").doc(firebaseUid).set(
        userData,
        { merge: true }
      );

      return {
        customToken,
        firebaseUid,
        success: true,
      };
    } catch (error) {
      logger.error("Error creating custom token:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      throw new HttpsError("internal", "Failed to create custom token");
    }
  }
);
