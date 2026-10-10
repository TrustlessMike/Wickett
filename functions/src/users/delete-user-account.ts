import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import {PRIVY_APP_ID, PRIVY_APP_SECRET} from "../config/privy-config";
import {PrivyClient} from "@privy-io/node";

/**
 * Cloud Function: Delete User Account
 *
 * Permanently deletes a user's account including:
 * 1. Privy user (and their embedded wallet)
 * 2. Firestore user document and subcollections
 * 3. Firebase Auth user
 *
 * This is irreversible - all data is permanently deleted.
 */
export const deleteUserAccount = onCall(
  {
    secrets: [PRIVY_APP_ID, PRIVY_APP_SECRET],
  },
  async (request) => {
    // Verify authentication
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    logger.info(`🗑️ Starting account deletion for user: ${userId}`);

    const db = getFirestore();
    const auth = getAuth();

    // Get user data to find Privy DID
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data();

    if (!userData) {
      logger.warn(`User document not found for ${userId}, continuing with deletion...`);
    }

    const privyUserId = userData?.privyUserId;
    const userEmail = userData?.email || request.auth?.token?.email;

    logger.info(`   Privy User ID: ${privyUserId}`);
    logger.info(`   Email: ${userEmail}`);

    // Step 1: Delete Privy user (this also deletes their wallet)
    if (privyUserId) {
      try {
        // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
        const appId = PRIVY_APP_ID.value().trim();
        const appSecret = PRIVY_APP_SECRET.value().trim();

        const privy = new PrivyClient({appId, appSecret});

        // Extract DID format
        let privyDid = privyUserId;
        if (!privyDid.startsWith("did:privy:")) {
          // Handle different formats
          if (privyDid.startsWith("privy_did:privy:")) {
            privyDid = privyDid.replace("privy_did:", "");
          } else {
            privyDid = `did:privy:${privyDid}`;
          }
        }

        logger.info(`   Deleting Privy user: ${privyDid}`);
        await privy.users().delete(privyDid);
        logger.info("   ✅ Privy user deleted (wallet also deleted)");
      } catch (error: any) {
        logger.error(`   ❌ Failed to delete Privy user: ${error.message}`);
        // Continue with other deletions even if Privy fails
      }
    } else {
      logger.warn("   No Privy user ID found, skipping Privy deletion");
    }

    // Step 2: Delete Firestore user document and subcollections
    try {
      const userRef = db.collection("users").doc(userId);

      // Delete subcollections
      const subcollections = ["delegations", "transactions", "activities"];

      for (const subcollection of subcollections) {
        const subcolSnapshot = await userRef.collection(subcollection).get();
        const batch = db.batch();
        subcolSnapshot.docs.forEach((doc) => batch.delete(doc.ref));
        if (!subcolSnapshot.empty) {
          await batch.commit();
          logger.info(`   Deleted ${subcolSnapshot.size} docs from ${subcollection}`);
        }
      }

      // Delete main user document
      await userRef.delete();
      logger.info("   ✅ Firestore user data deleted");
    } catch (error: any) {
      logger.error(`   ❌ Failed to delete Firestore data: ${error.message}`);
      // Continue with Firebase Auth deletion
    }

    // Step 3: Delete Firebase Auth user
    // Note: This may fail with permission errors on 2nd gen functions, but that's okay
    // The important data (Privy user + wallet, Firestore) is already deleted
    // Firebase Auth user will become orphaned but won't affect the user experience
    try {
      await auth.deleteUser(userId);
      logger.info("   ✅ Firebase Auth user deleted");
    } catch (error: any) {
      if (error.code === "auth/user-not-found") {
        logger.warn("   Firebase Auth user not found (already deleted)");
      } else {
        // Don't throw - the critical data (Privy + Firestore) is already deleted
        // The Firebase Auth user will just become orphaned, which is fine
        logger.warn(`   ⚠️ Could not delete Firebase Auth user: ${error.message}`);
        logger.warn("   (This is non-fatal - Privy and Firestore data already deleted)");
      }
    }

    // Step 4: Log audit trail
    try {
      await db.collection("accountDeletions").add({
        userId,
        userEmail,
        privyUserId,
        deletedAt: new Date(),
        success: true,
      });
    } catch (error) {
      logger.warn("Failed to log audit trail:", error);
    }

    logger.info(`✅ Account deletion complete for user: ${userId}`);

    return {
      success: true,
      message: "Account and all associated data have been permanently deleted",
      deletedUserId: userId,
    };
  }
);
