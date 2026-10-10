import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { HttpsError } from "firebase-functions/v2/https";
import { TRANSACTION_LIMITS } from "../config/solana-config";
import { lamportsToSol } from "../utils/solana-utils";

const db = admin.firestore();

interface TransactionRecord {
  userId: string;
  amount: number; // in lamports
  type: string;
  timestamp: admin.firestore.Timestamp;
  signature?: string;
  status: "pending" | "success" | "failed";
}

/**
 * Check user authentication
 */
export function requireAuth(context: { auth?: { uid: string } }): string {
  if (!context.auth) {
    throw new HttpsError(
      "unauthenticated",
      "Authentication required to perform this action"
    );
  }
  return context.auth.uid;
}

/**
 * Check daily rate limiting for user transactions (24-hour window)
 */
export async function checkDailyTransactionLimit(userId: string): Promise<void> {
  const now = new Date();
  const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  try {
    // Query transactions from the last 24 hours
    const transactionsRef = db
      .collection("transactions")
      .where("userId", "==", userId)
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(oneDayAgo))
      .where("status", "==", "success");

    const snapshot = await transactionsRef.get();
    const transactionCount = snapshot.size;

    if (transactionCount >= TRANSACTION_LIMITS.MAX_TRANSACTIONS_PER_USER_PER_DAY) {
      logger.warn(
        `Rate limit exceeded for user ${userId}: ${transactionCount} transactions in 24h`
      );
      throw new HttpsError(
        "resource-exhausted",
        `Daily transaction limit exceeded. Maximum ${TRANSACTION_LIMITS.MAX_TRANSACTIONS_PER_USER_PER_DAY} transactions per day.`
      );
    }

    logger.info(
      `Rate limit check passed for user ${userId}: ${transactionCount}/${TRANSACTION_LIMITS.MAX_TRANSACTIONS_PER_USER_PER_DAY} transactions`
    );
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("Error checking rate limit:", error);
    throw new HttpsError("internal", "Failed to check rate limit");
  }
}

/**
 * Check daily budget across all users
 */
export async function checkDailyBudget(amountLamports: number): Promise<void> {
  const now = new Date();
  const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  try {
    // Query all successful transactions from the last 24 hours
    const transactionsRef = db
      .collection("transactions")
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(oneDayAgo))
      .where("status", "==", "success");

    const snapshot = await transactionsRef.get();

    // Calculate total amount spent
    let totalSpent = 0;
    snapshot.forEach((doc) => {
      const data = doc.data() as TransactionRecord;
      totalSpent += data.amount || 0;
    });

    const totalSpentSol = lamportsToSol(totalSpent);
    const newTotalSol = lamportsToSol(totalSpent + amountLamports);

    if (newTotalSol > TRANSACTION_LIMITS.MAX_DAILY_BUDGET_SOL) {
      logger.warn(
        `Daily budget exceeded: ${newTotalSol}/${TRANSACTION_LIMITS.MAX_DAILY_BUDGET_SOL} SOL`
      );
      throw new HttpsError(
        "resource-exhausted",
        "Daily transaction budget exceeded. Please try again later."
      );
    }

    logger.info(
      `Daily budget check passed: ${newTotalSol}/${TRANSACTION_LIMITS.MAX_DAILY_BUDGET_SOL} SOL`
    );
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("Error checking daily budget:", error);
    throw new HttpsError("internal", "Failed to check daily budget");
  }
}

/**
 * Validate transaction amount
 */
export function validateAmount(amountLamports: number): void {
  if (amountLamports <= 0) {
    throw new HttpsError("invalid-argument", "Transaction amount must be greater than 0");
  }

  const maxLamports = TRANSACTION_LIMITS.MAX_SOL_PER_TRANSACTION * 1e9;
  if (amountLamports > maxLamports) {
    throw new HttpsError(
      "invalid-argument",
      `Transaction amount exceeds maximum of ${TRANSACTION_LIMITS.MAX_SOL_PER_TRANSACTION} SOL`
    );
  }
}

/**
 * Log transaction to Firestore
 */
export async function logTransaction(
  userId: string,
  type: string,
  amount: number,
  status: "pending" | "success" | "failed",
  signature?: string,
  metadata?: Record<string, unknown>
): Promise<string> {
  try {
    const transactionData: TransactionRecord & { metadata?: Record<string, unknown> } = {
      userId,
      type,
      amount,
      status,
      timestamp: admin.firestore.Timestamp.now(),
      ...(signature && { signature }),
      ...(metadata && { metadata }),
    };

    const docRef = await db.collection("transactions").add(transactionData);
    logger.info(`Transaction logged: ${docRef.id} - ${type} - ${status}`);
    return docRef.id;
  } catch (error) {
    logger.error("Error logging transaction:", error);
    throw error;
  }
}

/**
 * Update transaction status
 */
export async function updateTransactionStatus(
  transactionId: string,
  status: "pending" | "success" | "failed",
  signature?: string,
  error?: string
): Promise<void> {
  try {
    const updateData: Partial<TransactionRecord> & {
      signature?: string;
      error?: string;
      updatedAt: admin.firestore.Timestamp;
    } = {
      status,
      updatedAt: admin.firestore.Timestamp.now(),
      ...(signature && { signature }),
      ...(error && { error }),
    };

    await db.collection("transactions").doc(transactionId).update(updateData);
    logger.info(`Transaction ${transactionId} updated to ${status}`);
  } catch (error) {
    logger.error("Error updating transaction status:", error);
    throw error;
  }
}

/**
 * Complete security check for transaction
 */
export async function performSecurityChecks(
  context: { auth?: { uid: string } },
  amountLamports: number
): Promise<{ userId: string; transactionId: string }> {
  // 1. Check authentication
  const userId = requireAuth(context);

  // 2. Validate amount
  validateAmount(amountLamports);

  // 3. Check rate limiting - DISABLED FOR TESTING
  // await checkRateLimit(userId);

  // 4. Check daily budget - DISABLED FOR TESTING
  // await checkDailyBudget(amountLamports);

  // 5. Log transaction as pending
  const transactionId = await logTransaction(
    userId,
    "pending",
    amountLamports,
    "pending"
  );

  return { userId, transactionId };
}

/**
 * Get user transaction history
 */
export async function getUserTransactionHistory(
  userId: string,
  limit: number = 50
): Promise<Array<TransactionRecord & { id: string }>> {
  try {
    const snapshot = await db
      .collection("transactions")
      .where("userId", "==", userId)
      .orderBy("timestamp", "desc")
      .limit(limit)
      .get();

    const transactions: Array<TransactionRecord & { id: string }> = [];
    snapshot.forEach((doc) => {
      transactions.push({
        id: doc.id,
        ...(doc.data() as TransactionRecord),
      });
    });

    return transactions;
  } catch (error) {
    logger.error("Error fetching transaction history:", error);
    throw error;
  }
}
