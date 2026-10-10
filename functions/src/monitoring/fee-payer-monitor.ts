import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { Connection, PublicKey, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { defineSecret } from "firebase-functions/params";

// Secrets
const HELIUS_RPC_URL = defineSecret("HELIUS_RPC_URL");
const FEE_PAYER_PUBLIC_KEY = defineSecret("SOLANA_FEE_PAYER_PUBLIC_KEY");

// Minimum balance threshold: 0.1 SOL
const MIN_BALANCE_SOL = 0.1;
const MIN_BALANCE_LAMPORTS = MIN_BALANCE_SOL * LAMPORTS_PER_SOL;

/**
 * Scheduled function to monitor fee payer wallet balance
 * Runs every hour to ensure fee payer has sufficient SOL
 */
export const monitorFeePayerBalance = onSchedule(
  {
    schedule: "every 1 hours",
    timeZone: "America/Los_Angeles",
    secrets: [HELIUS_RPC_URL, FEE_PAYER_PUBLIC_KEY],
    memory: "256MiB",
  },
  async (event) => {
    try {
      const connection = new Connection(HELIUS_RPC_URL.value());
      const feePayerPubkey = new PublicKey(FEE_PAYER_PUBLIC_KEY.value());

      const balance = await connection.getBalance(feePayerPubkey);
      const balanceSOL = balance / LAMPORTS_PER_SOL;

      logger.info(`💰 Fee payer balance check: ${balanceSOL.toFixed(4)} SOL`);

      // Alert if balance is low
      if (balance < MIN_BALANCE_LAMPORTS) {
        logger.error(
          `⚠️ FEE PAYER BALANCE LOW! ⚠️\n` +
          `Current: ${balanceSOL.toFixed(4)} SOL\n` +
          `Minimum: ${MIN_BALANCE_SOL} SOL\n` +
          `Fee payer: ${feePayerPubkey.toBase58()}\n` +
          `ACTION REQUIRED: Top up the fee payer wallet immediately!`
        );

        // TODO: Add email/SMS alert integration
        // - SendGrid for email
        // - Twilio for SMS
        // - Firebase Cloud Messaging for push notifications
      } else {
        logger.info(`✅ Fee payer balance healthy: ${balanceSOL.toFixed(4)} SOL`);
      }
    } catch (error) {
      logger.error("Failed to check fee payer balance:", error);
      throw error;
    }
  }
);

/**
 * Manual check endpoint for fee payer balance
 * Callable from iOS app or admin dashboard
 */
export const checkFeePayerBalance = onCall(
  {
    secrets: [HELIUS_RPC_URL, FEE_PAYER_PUBLIC_KEY],
    memory: "256MiB",
  },
  async (request) => {
    try {
      const connection = new Connection(HELIUS_RPC_URL.value());
      const feePayerPubkey = new PublicKey(FEE_PAYER_PUBLIC_KEY.value());

      const balance = await connection.getBalance(feePayerPubkey);
      const balanceSOL = balance / LAMPORTS_PER_SOL;

      const isLow = balance < MIN_BALANCE_LAMPORTS;

      logger.info(
        `Manual balance check: ${balanceSOL.toFixed(4)} SOL` +
        `(${isLow ? "LOW" : "OK"})`
      );

      return {
        success: true,
        address: feePayerPubkey.toBase58(),
        balance: balanceSOL,
        balanceLamports: balance,
        isLow: isLow,
        threshold: MIN_BALANCE_SOL,
        status: isLow ? "LOW" : "OK",
        message: isLow
          ? `Balance is low! Please top up (current: ${balanceSOL.toFixed(4)} SOL)`
          : `Balance is healthy (current: ${balanceSOL.toFixed(4)} SOL)`
      };
    } catch (error) {
      logger.error("Failed to check fee payer balance:", error);
      throw new HttpsError(
        "internal",
        `Failed to check balance: ${error instanceof Error ? error.message : "Unknown error"}`
      );
    }
  }
);
