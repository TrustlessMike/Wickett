import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFeePayerPublicKey, SOLANA_FEE_PAYER_PRIVATE_KEY } from "../config/solana-config";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

/**
 * Get the fee payer public key (dev wallet)
 * Admin-only function for getting the dev wallet address
 */
export const getFeePayerAddress = onCall(
  {
    secrets: [SOLANA_FEE_PAYER_PRIVATE_KEY],
    invoker: "public"
  },
  async (request) => {
  try {
    const feePayerAddress = getFeePayerPublicKey().toString();

    logger.info(`Fee payer address: ${feePayerAddress}`);

    return {
      success: true,
      address: feePayerAddress,
      displayName: "Wickett Team"
    };
  } catch (error) {
    logger.error("Failed to get fee payer address:", error);
    throw new HttpsError("internal", "Failed to get fee payer address");
  }
  }
);

/**
 * Setup the Wickett Team user document with username for searchability
 * This makes the fee payer wallet findable in user search
 */
export const setupWickettTeamUser = onCall(
  {
    secrets: [SOLANA_FEE_PAYER_PRIVATE_KEY],
    invoker: "public"
  },
  async (request) => {
    // Require authentication
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    try {
      const db = getFirestore();
      const feePayerAddress = getFeePayerPublicKey().toString();
      const username = "wickettteam";
      const displayName = "Wickett Team";

      // Check if user document already exists
      const existingQuery = await db
        .collection("users")
        .where("walletAddress", "==", feePayerAddress)
        .limit(1)
        .get();

      if (!existingQuery.empty) {
        // Update existing document
        const doc = existingQuery.docs[0];
        await doc.ref.update({
          username,
          displayName,
          updatedAt: FieldValue.serverTimestamp(),
        });
        logger.info(`Updated Wickett Team user: ${feePayerAddress} with username: ${username}`);
      } else {
        // Create new document
        await db.collection("users").add({
          walletAddress: feePayerAddress,
          username,
          displayName,
          isPlaceholder: true,
          createdAt: FieldValue.serverTimestamp(),
        });
        logger.info(`Created Wickett Team user: ${feePayerAddress} with username: ${username}`);
      }

      return {
        success: true,
        walletAddress: feePayerAddress,
        username,
        displayName,
      };
    } catch (error) {
      logger.error("Failed to setup Wickett Team user:", error);
      throw new HttpsError("internal", "Failed to setup Wickett Team user");
    }
  }
);
