import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { PublicKey, SystemProgram } from "@solana/web3.js";
import * as logger from "firebase-functions/logger";
import {
  HELIUS_RPC_URL,
  SOLANA_FEE_PAYER_PRIVATE_KEY,
  getFeePayerPublicKey,
  getSolanaConnection,
} from "../config/solana-config";
import {
  buildVersionedTransaction,
  signTransactionWithFeePayer,
  simulateTransaction,
  serializeTransaction,
  estimateTransactionFee,
} from "../solana/transaction-builder";
import {
  performSecurityChecks,
  updateTransactionStatus,
} from "../middleware/transaction-security";
import { isValidSolanaAddress, createErrorResponse, createSuccessResponse } from "../utils/solana-utils";

interface SponsorSolTransferV2Request {
  destinationAddress: string;
  amountLamports: number;
  userWalletAddress?: string; // Optional - for testing, will get from Firestore if not provided
  memo?: string;
}

interface SponsorSolTransferV2Response {
  success: boolean;
  partiallySignedTransaction?: string; // base64
  estimatedFee?: number;
  error?: string;
  code?: string;
}

/**
 * Sponsor a SOL transfer transaction - V2 with user signing
 *
 * Flow:
 * 1. Backend builds transaction
 * 2. Backend signs with fee payer (for gas sponsorship)
 * 3. Returns partially-signed transaction to client
 * 4. Client gets user signature via Privy
 * 5. Client calls broadcastSignedTransaction to submit
 */
export const sponsorSolTransferV2 = onCall<
  SponsorSolTransferV2Request,
  Promise<SponsorSolTransferV2Response>
>(
  {
    secrets: [HELIUS_RPC_URL, SOLANA_FEE_PAYER_PRIVATE_KEY],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (
    request: CallableRequest<SponsorSolTransferV2Request>
  ): Promise<SponsorSolTransferV2Response> => {
    const { destinationAddress, amountLamports, userWalletAddress, memo } = request.data;

    try {
      logger.info("🚀 [V2] Starting sponsored SOL transfer build");
      logger.info(`Destination: ${destinationAddress}`);
      logger.info(`Amount: ${amountLamports} lamports (${amountLamports / 1e9} SOL)`);
      if (memo) {
        logger.info(`Memo: ${memo}`);
      }

      // Validate destination address
      if (!isValidSolanaAddress(destinationAddress)) {
        return createErrorResponse(
          "INVALID_ADDRESS",
          "Invalid destination address"
        ) as SponsorSolTransferV2Response;
      }

      // Perform security checks (auth, rate limiting, amount validation, logging)
      const { userId, transactionId } = await performSecurityChecks(
        request,
        amountLamports
      );

      try {
        // Get user wallet address from request or Firestore
        let userWalletFromRequest = userWalletAddress;

        if (!userWalletFromRequest) {
          // Get from Firestore (from Privy)
          const admin = await import("firebase-admin");
          const userDoc = await admin
            .firestore()
            .collection("users")
            .doc(userId)
            .get();

          const userData = userDoc.data();
          userWalletFromRequest = userData?.walletAddress;

          if (!userWalletFromRequest) {
            throw new HttpsError(
              "failed-precondition",
              "User wallet address not found. Please ensure your wallet is set up."
            );
          }
        }

        logger.info(`User wallet: ${userWalletFromRequest}`);

        // Validate user has sufficient balance
        const connection = getSolanaConnection();
        const userBalance = await connection.getBalance(new PublicKey(userWalletFromRequest));

        if (userBalance < amountLamports) {
          await updateTransactionStatus(
            transactionId,
            "failed",
            undefined,
            "Insufficient balance"
          );
          return createErrorResponse(
            "INSUFFICIENT_BALANCE",
            `Insufficient balance. Required: ${amountLamports / 1e9} SOL, Available: ${userBalance / 1e9} SOL`
          ) as SponsorSolTransferV2Response;
        }

        // Build transfer instruction from user to destination
        const instructions = [
          SystemProgram.transfer({
            fromPubkey: new PublicKey(userWalletFromRequest),
            toPubkey: new PublicKey(destinationAddress),
            lamports: amountLamports,
          })
        ];

        // Add memo instruction if provided
        if (memo && memo.trim().length > 0) {
          const memoProgram = new PublicKey("MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr");
          const memoInstruction = {
            keys: [],
            programId: memoProgram,
            data: Buffer.from(memo, "utf-8"),
          };
          instructions.push(memoInstruction);
        }

        // Build transaction with fee payer as backend wallet
        const transaction = await buildVersionedTransaction({
          instructions,
          feePayer: getFeePayerPublicKey(), // Backend pays the fee
        });

        // Simulate transaction first
        logger.info("🔍 Simulating transaction...");
        const simulation = await simulateTransaction(transaction);

        if (!simulation.success) {
          await updateTransactionStatus(
            transactionId,
            "failed",
            undefined,
            `Simulation failed: ${simulation.error}`
          );
          return createErrorResponse(
            "SIMULATION_FAILED",
            `Transaction simulation failed: ${simulation.error}`,
            { logs: simulation.logs }
          ) as SponsorSolTransferV2Response;
        }

        logger.info("✅ Simulation successful");

        // Sign transaction with fee payer ONLY
        // User will sign on client side before broadcast
        signTransactionWithFeePayer(transaction);

        logger.info("✅ Transaction signed with fee payer (partial signature)");

        // Estimate fee for informational purposes
        const estimatedFee = await estimateTransactionFee(transaction);

        // Serialize to base64 for client
        const partiallySignedTx = serializeTransaction(transaction);

        logger.info("✅ Partially-signed transaction ready for client");
        logger.info(`Transaction ID: ${transactionId}`);

        // Update transaction status to pending (waiting for user signature)
        await updateTransactionStatus(
          transactionId,
          "pending",
          undefined,
          "Waiting for user signature"
        );

        return createSuccessResponse(
          {
            partiallySignedTransaction: partiallySignedTx,
            estimatedFee,
          },
          "Transaction built successfully. Ready for user signature."
        ) as SponsorSolTransferV2Response;
      } catch (error) {
        // Update transaction status to failed
        await updateTransactionStatus(
          transactionId,
          "failed",
          undefined,
          error instanceof Error ? error.message : String(error)
        );

        throw error;
      }
    } catch (error) {
      logger.error("❌ [V2] Sponsored SOL transfer build failed:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      return createErrorResponse(
        "TRANSACTION_BUILD_FAILED",
        error instanceof Error ? error.message : "Failed to build transaction",
        { error }
      ) as SponsorSolTransferV2Response;
    }
  }
);
