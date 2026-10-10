import {
  Connection,
  PublicKey,
  Transaction,
  VersionedTransaction,
  TransactionMessage,
  TransactionInstruction,
  SystemProgram,
  Keypair,
  sendAndConfirmTransaction,
  VersionedTransactionResponse,
  Commitment,
} from "@solana/web3.js";
import * as logger from "firebase-functions/logger";
import { retryWithBackoff } from "../utils/solana-utils";
import { getSolanaConnection, getFeePayerKeypair } from "../config/solana-config";

export interface TransactionBuilderOptions {
  feePayer?: PublicKey;
  recentBlockhash?: string;
  instructions: TransactionInstruction[];
  signers?: Keypair[];
}

/**
 * Get recent blockhash with retry
 */
export async function getRecentBlockhash(
  connection?: Connection
): Promise<{ blockhash: string; lastValidBlockHeight: number }> {
  const conn = connection || getSolanaConnection();

  return retryWithBackoff(async () => {
    const { blockhash, lastValidBlockHeight } = await conn.getLatestBlockhash("confirmed");
    logger.info(`Got recent blockhash: ${blockhash}`);
    return { blockhash, lastValidBlockHeight };
  });
}

/**
 * Build a versioned transaction with fee payer
 */
export async function buildVersionedTransaction(
  options: TransactionBuilderOptions
): Promise<VersionedTransaction> {
  const connection = getSolanaConnection();
  const feePayerKeypair = getFeePayerKeypair();

  try {
    // Get recent blockhash if not provided
    const { blockhash } = options.recentBlockhash
      ? { blockhash: options.recentBlockhash }
      : await getRecentBlockhash(connection);

    // Build transaction message
    const messageV0 = new TransactionMessage({
      payerKey: options.feePayer || feePayerKeypair.publicKey,
      recentBlockhash: blockhash,
      instructions: options.instructions,
    }).compileToV0Message();

    // Create versioned transaction
    const transaction = new VersionedTransaction(messageV0);

    logger.info("✅ Versioned transaction built successfully");
    return transaction;
  } catch (error) {
    logger.error("❌ Failed to build versioned transaction:", error);
    throw error;
  }
}

/**
 * Sign transaction with fee payer
 */
export function signTransactionWithFeePayer(
  transaction: VersionedTransaction | Transaction
): void {
  const feePayerKeypair = getFeePayerKeypair();

  try {
    if (transaction instanceof VersionedTransaction) {
      transaction.sign([feePayerKeypair]);
    } else {
      transaction.sign(feePayerKeypair);
    }
    logger.info("✅ Transaction signed with fee payer");
  } catch (error) {
    logger.error("❌ Failed to sign transaction:", error);
    throw error;
  }
}

/**
 * Send and confirm transaction
 */
export async function sendAndConfirmTransactionWithRetry(
  transaction: VersionedTransaction | Transaction,
  options: {
    maxRetries?: number;
    commitment?: Commitment;
  } = {}
): Promise<string> {
  const connection = getSolanaConnection();
  const { maxRetries = 3, commitment = "confirmed" } = options;

  return retryWithBackoff(
    async () => {
      try {
        // Send raw transaction
        const signature = await connection.sendRawTransaction(
          transaction.serialize(),
          {
            skipPreflight: false,
            preflightCommitment: commitment,
          }
        );

        logger.info(`Transaction sent: ${signature}`);

        // Confirm transaction
        const latestBlockhash = await connection.getLatestBlockhash();
        await connection.confirmTransaction(
          {
            signature,
            blockhash: latestBlockhash.blockhash,
            lastValidBlockHeight: latestBlockhash.lastValidBlockHeight,
          },
          commitment
        );

        logger.info(`✅ Transaction confirmed: ${signature}`);
        return signature;
      } catch (error) {
        logger.error("❌ Transaction failed:", error);
        throw error;
      }
    },
    maxRetries,
    2000
  );
}

/**
 * Simulate transaction before sending
 */
export async function simulateTransaction(
  transaction: VersionedTransaction | Transaction
): Promise<{ success: boolean; error?: string; logs?: string[] }> {
  const connection = getSolanaConnection();

  try {
    const simulation =
      transaction instanceof VersionedTransaction
        ? await connection.simulateTransaction(transaction)
        : await connection.simulateTransaction(transaction);

    if (simulation.value.err) {
      logger.warn("Transaction simulation failed:", simulation.value.err);
      return {
        success: false,
        error: JSON.stringify(simulation.value.err),
        logs: simulation.value.logs || [],
      };
    }

    logger.info("✅ Transaction simulation successful");
    return {
      success: true,
      logs: simulation.value.logs || [],
    };
  } catch (error) {
    logger.error("❌ Transaction simulation error:", error);
    return {
      success: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Get transaction details
 */
/* export async function getTransactionDetails(
  signature: string,
  commitment: Commitment = "confirmed"
): Promise<VersionedTransactionResponse | null> {
  const connection = getSolanaConnection();

  try {
    const transaction = await connection.getTransaction(signature, {
      commitment,
      maxSupportedTransactionVersion: 0,
    });

    return transaction;
  } catch (error) {
    logger.error("Failed to get transaction details:", error);
    return null;
  }
} */

/**
 * Build and send a simple SOL transfer transaction
 */
export async function buildAndSendSolTransfer(
  fromPubkey: PublicKey,
  toPubkey: PublicKey,
  lamports: number,
  signers?: Keypair[]
): Promise<string> {
  const instruction = SystemProgram.transfer({
    fromPubkey,
    toPubkey,
    lamports,
  });

  const transaction = await buildVersionedTransaction({
    instructions: [instruction],
    signers,
  });

  // Sign with fee payer
  signTransactionWithFeePayer(transaction);

  // If additional signers, add their signatures
  if (signers && signers.length > 0) {
    transaction.sign(signers);
  }

  // Simulate first
  const simulation = await simulateTransaction(transaction);
  if (!simulation.success) {
    throw new Error(`Transaction simulation failed: ${simulation.error}`);
  }

  // Send and confirm
  const signature = await sendAndConfirmTransactionWithRetry(transaction);
  return signature;
}

/**
 * Estimate transaction fee
 */
export async function estimateTransactionFee(
  transaction: VersionedTransaction | Transaction
): Promise<number> {
  const connection = getSolanaConnection();

  try {
    const fee = await connection.getFeeForMessage(
      transaction instanceof VersionedTransaction
        ? transaction.message
        : transaction.compileMessage(),
      "confirmed"
    );

    return fee.value || 5000;
  } catch (error) {
    logger.error("Failed to estimate transaction fee:", error);
    return 5000; // Default fee estimate
  }
}

// ============================================================================
// V2 SPONSORSHIP UTILITIES
// ============================================================================

/**
 * Serialize VersionedTransaction to base64 string
 * Used for V2 sponsorship flow where backend returns partially-signed transaction
 */
export function serializeTransaction(transaction: VersionedTransaction): string {
  try {
    const serialized = transaction.serialize();
    const base64 = Buffer.from(serialized).toString("base64");
    logger.info("✅ Transaction serialized to base64");
    return base64;
  } catch (error) {
    logger.error("❌ Failed to serialize transaction:", error);
    throw error;
  }
}

/**
 * Deserialize base64 string to VersionedTransaction
 * Used when receiving user-signed transaction from client
 */
export function deserializeTransaction(base64: string): VersionedTransaction {
  try {
    const buffer = Buffer.from(base64, "base64");
    const transaction = VersionedTransaction.deserialize(buffer);
    logger.info("✅ Transaction deserialized from base64");
    return transaction;
  } catch (error) {
    logger.error("❌ Failed to deserialize transaction:", error);
    throw error;
  }
}

/**
 * Verify transaction has required signatures
 * Returns true if transaction has at least the expected number of signatures
 */
export function verifyTransactionSignatures(
  transaction: VersionedTransaction,
  expectedSigners: PublicKey[]
): boolean {
  try {
    const signatures = transaction.signatures;

    // Check we have enough signatures
    if (signatures.length < expectedSigners.length) {
      logger.warn(
        `Insufficient signatures: expected ${expectedSigners.length}, got ${signatures.length}`
      );
      return false;
    }

    // Verify no null signatures
    const hasNullSignature = signatures.some(
      (sig) => sig.every((byte) => byte === 0)
    );

    if (hasNullSignature) {
      logger.warn("Transaction contains null signatures");
      return false;
    }

    logger.info(`✅ Transaction has ${signatures.length} valid signatures`);
    return true;
  } catch (error) {
    logger.error("❌ Failed to verify transaction signatures:", error);
    return false;
  }
}
