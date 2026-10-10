import { Connection, Keypair, PublicKey } from "@solana/web3.js";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import bs58 from "bs58";

// Define secrets for Helius RPC and fee payer private key
export const HELIUS_RPC_URL = defineSecret("HELIUS_RPC_URL");
export const HELIUS_API_KEY = defineSecret("HELIUS_API_KEY");
export const SOLANA_FEE_PAYER_PRIVATE_KEY = defineSecret("SOLANA_FEE_PAYER_PRIVATE_KEY");

// Helius Webhook Configuration
export const HELIUS_WEBHOOK_ID = "432720ff-af45-42cb-aca9-b1af47559bd1";

// Solana network configuration
export const SOLANA_NETWORK = "mainnet-beta";
export const COMMITMENT = "confirmed";
export const INDEX_VERSION = 3; // Firestore indexes corrected

// Transaction limits and security configuration
export const TRANSACTION_LIMITS = {
  MAX_SOL_PER_TRANSACTION: 0.1, // Maximum 0.1 SOL per transaction
  MAX_TRANSACTIONS_PER_USER_PER_DAY: 50,
  MAX_DAILY_BUDGET_SOL: 10, // Maximum 10 SOL per day across all users
};

// Platform fee configuration
export const PLATFORM_FEES = {
  // Fee in basis points (bps): 50 bps = 0.5%
  SWAP_FEE_BPS: 50, // 0.5% platform fee on all swaps
  PAYMENT_REQUEST_FEE_BPS: 50, // 0.5% on payment request conversions

  // Minimum fee in SOL (to cover very small transactions)
  MIN_FEE_SOL: 0.001, // ~$0.20 at $200/SOL

  // Jupiter takes 2.5% of platform fee, you keep 97.5%
  JUPITER_CUT_PERCENT: 2.5,
};

// Platform fee collection wallet
export const PLATFORM_FEE_WALLET = "637pBRjR6d8i5ysViJhs3pQg5K7QfEUYCpkpDpGWZQ7w";

// Jupiter Ultra API Referral Account
export const JUPITER_REFERRAL_ACCOUNT = "GwRXLPo1raGRViy4QAvYgj2UKNqufesDzWz5rpZ8j3z4";

// Whitelisted program IDs for custom instruction execution
export const WHITELISTED_PROGRAM_IDS = new Set<string>([
  "11111111111111111111111111111111", // System Program
  "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA", // SPL Token Program
  "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb", // Token-2022 (Token Extensions)
  "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4", // Jupiter V6
  "JUP4Fb2cqiRUcaTHdrPC8h2gNsA2ETXiPDD33WcGuJB", // Jupiter V4
  "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL", // Associated Token Program
  // Add more program IDs as needed
]);

// Connection instance (singleton)
let connection: Connection | null = null;
let feePayerKeypair: Keypair | null = null;

/**
 * Get or create Solana RPC connection
 */
export function getSolanaConnection(): Connection {
  if (!connection) {
    const rpcUrl = HELIUS_RPC_URL.value();
    connection = new Connection(rpcUrl, COMMITMENT);
    logger.info(`✅ Solana connection initialized: ${SOLANA_NETWORK}`);
  }
  return connection;
}

/**
 * Get or create fee payer keypair from secret
 */
export function getFeePayerKeypair(): Keypair {
  if (!feePayerKeypair) {
    try {
      const privateKeySecret = SOLANA_FEE_PAYER_PRIVATE_KEY.value();

      // Try to parse as JSON array first (new format)
      let privateKeyBytes: Uint8Array;
      try {
        const secretKeyArray = JSON.parse(privateKeySecret);
        if (Array.isArray(secretKeyArray)) {
          privateKeyBytes = new Uint8Array(secretKeyArray);
        } else {
          throw new Error("Secret is not an array");
        }
      } catch {
        // Fallback to base58 format (legacy)
        privateKeyBytes = bs58.decode(privateKeySecret);
      }

      feePayerKeypair = Keypair.fromSecretKey(privateKeyBytes);
      logger.info(`✅ Fee payer wallet loaded: ${feePayerKeypair.publicKey.toBase58()}`);
    } catch (error) {
      logger.error("❌ Failed to load fee payer keypair:", error);
      throw new Error("Failed to initialize fee payer wallet");
    }
  }
  return feePayerKeypair;
}

/**
 * Get fee payer public key
 */
export function getFeePayerPublicKey(): PublicKey {
  return getFeePayerKeypair().publicKey;
}

/**
 * Validate if a program ID is whitelisted
 */
export function isWhitelistedProgram(programId: string): boolean {
  return WHITELISTED_PROGRAM_IDS.has(programId);
}

/**
 * Check if fee payer has sufficient balance
 */
export async function checkFeePayerBalance(requiredLamports: number = 5000000): Promise<boolean> {
  try {
    const connection = getSolanaConnection();
    const feePayerPubkey = getFeePayerPublicKey();
    const balance = await connection.getBalance(feePayerPubkey);

    if (balance < requiredLamports) {
      logger.warn(`⚠️ Fee payer balance low: ${balance / 1e9} SOL`);
      return false;
    }

    return true;
  } catch (error) {
    logger.error("❌ Failed to check fee payer balance:", error);
    return false;
  }
}

/**
 * Get fee payer balance in SOL
 */
export async function getFeePayerBalance(): Promise<number> {
  try {
    const connection = getSolanaConnection();
    const feePayerPubkey = getFeePayerPublicKey();
    const balance = await connection.getBalance(feePayerPubkey);
    return balance / 1e9; // Convert lamports to SOL
  } catch (error) {
    logger.error("❌ Failed to get fee payer balance:", error);
    throw error;
  }
}
