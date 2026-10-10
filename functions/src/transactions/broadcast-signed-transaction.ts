import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { PublicKey } from "@solana/web3.js";
import * as logger from "firebase-functions/logger";
import {
  HELIUS_RPC_URL,
  SOLANA_FEE_PAYER_PRIVATE_KEY,
  getFeePayerPublicKey,
} from "../config/solana-config";
import {
  deserializeTransaction,
  verifyTransactionSignatures,
  sendAndConfirmTransactionWithRetry,
} from "../solana/transaction-builder";
import { createErrorResponse, createSuccessResponse } from "../utils/solana-utils";

interface BroadcastSignedTransactionRequest {
  signedTransaction: string; // base64 fully-signed VersionedTransaction
  transactionType: "sol_transfer" | "spl_transfer" | "swap" | "custom";
  recipientAddress?: string; // For tracking recent recipients
  amountUsd?: number; // USD value of the transaction
  recipientDisplay?: string; // Display name or username of recipient
}

interface BroadcastSignedTransactionResponse {
  success: boolean;
  transactionHash?: string;
  explorerUrl?: string;
  error?: string;
  code?: string;
}

/**
 * Broadcast a user-signed transaction to Solana network
 *
 * Flow:
 * 1. Client sends fully-signed transaction (user + fee payer signatures)
 * 2. Backend deserializes and verifies signatures
 * 3. Backend broadcasts to network
 * 4. Backend logs to Firestore
 * 5. Returns transaction signature
 */
export const broadcastSignedTransaction = onCall<
  BroadcastSignedTransactionRequest,
  Promise<BroadcastSignedTransactionResponse>
>(
  {
    secrets: [HELIUS_RPC_URL, SOLANA_FEE_PAYER_PRIVATE_KEY],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (
    request: CallableRequest<BroadcastSignedTransactionRequest>
  ): Promise<BroadcastSignedTransactionResponse> => {
    const { signedTransaction, transactionType, recipientAddress, amountUsd, recipientDisplay } = request.data;

    try {
      logger.info("🚀 [V2] Broadcasting signed transaction");
      logger.info(`Transaction type: ${transactionType}`);

      // Verify user is authenticated
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "User must be authenticated");
      }

      const userId = request.auth.uid;
      logger.info(`User ID: ${userId}`);

      // Get user wallet address
      const admin = await import("firebase-admin");
      const userDoc = await admin
        .firestore()
        .collection("users")
        .doc(userId)
        .get();

      const userData = userDoc.data();
      const userWalletAddress = userData?.walletAddress;

      if (!userWalletAddress) {
        throw new HttpsError(
          "failed-precondition",
          "User wallet address not found"
        );
      }

      // Deserialize the fully-signed transaction
      logger.info("📦 Deserializing fully-signed transaction...");
      const transaction = deserializeTransaction(signedTransaction);

      // Verify transaction has required signatures
      // Should have at least 2: user + fee payer
      const expectedSigners = [
        new PublicKey(userWalletAddress),
        getFeePayerPublicKey(),
      ];

      const hasValidSignatures = verifyTransactionSignatures(
        transaction,
        expectedSigners
      );

      if (!hasValidSignatures) {
        logger.error("❌ Transaction missing required signatures");
        return createErrorResponse(
          "INVALID_SIGNATURES",
          "Transaction is missing required signatures"
        ) as BroadcastSignedTransactionResponse;
      }

      logger.info("✅ Transaction signatures verified");

      // Send transaction to network
      logger.info("📤 Broadcasting transaction to Solana network...");
      const signature = await sendAndConfirmTransactionWithRetry(transaction, {
        maxRetries: 3,
      });

      logger.info(`✅ Transaction confirmed: ${signature}`);

      const explorerUrl = `https://solscan.io/tx/${signature}?cluster=mainnet`;

      // Log transaction to Firestore
      const transactionDoc = await admin
        .firestore()
        .collection("solana_transactions")
        .add({
          user_id: userId,
          user_wallet: userWalletAddress,
          transaction_type: transactionType,
          signature,
          status: "success",
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          explorer_url: explorerUrl,
          recipient_address: recipientAddress || null,
          recipient_display: recipientDisplay || null,
          amount_usd: amountUsd || 0,
        });

      logger.info(`Transaction logged: ${transactionDoc.id}`);

      // Track recent recipient if provided
      if (recipientAddress) {
        try {
          const { saveRecentRecipient } = await import("../middleware/recipients-tracker");
          await saveRecentRecipient(
            userId,
            recipientAddress,
            transactionType === "spl_transfer" ? "SPL" : "SOL"
          );
        } catch (error) {
          // Non-critical error, just log it
          logger.warn("Failed to save recent recipient:", error);
        }
      }

      return createSuccessResponse(
        {
          transactionHash: signature,
          explorerUrl,
        },
        `Transaction confirmed: ${signature}`
      ) as BroadcastSignedTransactionResponse;
    } catch (error) {
      logger.error("❌ [V2] Transaction broadcast failed:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      return createErrorResponse(
        "BROADCAST_FAILED",
        error instanceof Error ? error.message : "Failed to broadcast transaction",
        { error }
      ) as BroadcastSignedTransactionResponse;
    }
  }
);
