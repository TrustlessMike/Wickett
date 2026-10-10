import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { PublicKey } from "@solana/web3.js";
import {
  getAssociatedTokenAddress,
  createAssociatedTokenAccountInstruction,
  createTransferInstruction,
  TOKEN_PROGRAM_ID,
} from "@solana/spl-token";
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

interface SponsorSplTransferV2Request {
  tokenMintAddress: string;
  destinationAddress: string;
  amount: number; // Amount in token's smallest unit
  decimals: number;
  userWalletAddress?: string; // Optional - for testing, will get from Firestore if not provided
  memo?: string;
}

interface SponsorSplTransferV2Response {
  success: boolean;
  partiallySignedTransaction?: string; // base64
  ataCreated?: boolean; // if destination ATA was created
  estimatedFee?: number;
  error?: string;
  code?: string;
}

/**
 * Sponsor an SPL token transfer transaction - V2 with user signing
 *
 * Flow:
 * 1. Backend builds transaction (including ATA creation if needed)
 * 2. Backend signs with fee payer (for gas sponsorship)
 * 3. Returns partially-signed transaction to client
 * 4. Client gets user signature via Privy
 * 5. Client calls broadcastSignedTransaction to submit
 */
export const sponsorSplTransferV2 = onCall<
  SponsorSplTransferV2Request,
  Promise<SponsorSplTransferV2Response>
>(
  {
    secrets: [HELIUS_RPC_URL, SOLANA_FEE_PAYER_PRIVATE_KEY],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (
    request: CallableRequest<SponsorSplTransferV2Request>
  ): Promise<SponsorSplTransferV2Response> => {
    const { tokenMintAddress, destinationAddress, amount, decimals, userWalletAddress, memo } = request.data;

    try {
      logger.info("🚀 [V2] Starting sponsored SPL transfer build");
      logger.info(`Token Mint: ${tokenMintAddress}`);
      logger.info(`Destination: ${destinationAddress}`);
      logger.info(`Amount: ${amount} (${amount / Math.pow(10, decimals)} tokens)`);
      if (memo) {
        logger.info(`Memo: ${memo}`);
      }

      // Validate addresses
      if (!isValidSolanaAddress(tokenMintAddress)) {
        return createErrorResponse(
          "INVALID_MINT_ADDRESS",
          "Invalid token mint address"
        ) as SponsorSplTransferV2Response;
      }

      if (!isValidSolanaAddress(destinationAddress)) {
        return createErrorResponse(
          "INVALID_ADDRESS",
          "Invalid destination address"
        ) as SponsorSplTransferV2Response;
      }

      // Perform security checks
      const { userId, transactionId } = await performSecurityChecks(
        request,
        amount
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

        const connection = getSolanaConnection();
        const mintPubkey = new PublicKey(tokenMintAddress);
        const userPubkey = new PublicKey(userWalletFromRequest);
        const destinationPubkey = new PublicKey(destinationAddress);

        // Get user's token account
        const userTokenAccount = await getAssociatedTokenAddress(
          mintPubkey,
          userPubkey
        );

        // Check if user has the token account and sufficient balance
        const userTokenAccountInfo = await connection.getAccountInfo(userTokenAccount);
        if (!userTokenAccountInfo) {
          await updateTransactionStatus(
            transactionId,
            "failed",
            undefined,
            "User does not have a token account for this token"
          );
          return createErrorResponse(
            "NO_TOKEN_ACCOUNT",
            "You don't have this token in your wallet"
          ) as SponsorSplTransferV2Response;
        }

        // Get destination token account
        const destinationTokenAccount = await getAssociatedTokenAddress(
          mintPubkey,
          destinationPubkey
        );

        // Check if destination ATA exists
        const destinationAccountInfo = await connection.getAccountInfo(destinationTokenAccount);
        const needsATACreation = !destinationAccountInfo;

        logger.info(`Destination ATA exists: ${!needsATACreation}`);

        // Build instructions
        const instructions = [];

        // Create ATA for destination if needed
        if (needsATACreation) {
          logger.info("Creating destination ATA...");
          instructions.push(
            createAssociatedTokenAccountInstruction(
              getFeePayerPublicKey(), // Fee payer creates the account
              destinationTokenAccount,
              destinationPubkey,
              mintPubkey
            )
          );
        }

        // Add transfer instruction
        instructions.push(
          createTransferInstruction(
            userTokenAccount, // Source
            destinationTokenAccount, // Destination
            userPubkey, // Owner (will need to sign)
            amount,
            [],
            TOKEN_PROGRAM_ID
          )
        );

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
          ) as SponsorSplTransferV2Response;
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
        if (needsATACreation) {
          logger.info("📝 Destination ATA will be created");
        }

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
            ataCreated: needsATACreation,
            estimatedFee,
          },
          "Transaction built successfully. Ready for user signature."
        ) as SponsorSplTransferV2Response;
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
      logger.error("❌ [V2] Sponsored SPL transfer build failed:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      return createErrorResponse(
        "TRANSACTION_BUILD_FAILED",
        error instanceof Error ? error.message : "Failed to build transaction",
        { error }
      ) as SponsorSplTransferV2Response;
    }
  }
);
