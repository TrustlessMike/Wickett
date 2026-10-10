import * as logger from "firebase-functions/logger";
import {getFirestore, FieldValue} from "firebase-admin/firestore";

/**
 * Auto-swap log entry
 */
export interface AutoSwapLog {
  userId: string;
  delegationId: string;
  timestamp: FirebaseFirestore.Timestamp;

  // Input details
  input: {
    token: string;
    symbol: string;
    amount: number;
    valueUsd: number;
  };

  // Output details
  outputs: {
    token: string;
    symbol: string;
    amount: number;
    valueUsd: number;
    signature: string;
  }[];

  // Fees
  fees?: {
    platform: number;
    jupiter: number;
    network: number;
  };

  // Status
  status: "success" | "failed" | "partial";
  error?: string;

  // Metadata
  totalValueSwapped: number;
  solscanUrl?: string;
}

/**
 * Log successful auto-swap
 */
export async function logAutoSwap(log: Omit<AutoSwapLog, "timestamp" | "solscanUrl">): Promise<string> {
  const db = getFirestore();

  const signature = log.outputs[0]?.signature;
  const solscanUrl = signature
    ? `https://solscan.io/tx/${signature}`
    : undefined;

  const docRef = await db.collection("auto_swap_logs").add({
    ...log,
    timestamp: FieldValue.serverTimestamp(),
    solscanUrl,
  });

  logger.info(`📝 Auto-swap logged: ${docRef.id}`);
  logger.info(`   User: ${log.userId}`);
  logger.info(`   Input: ${log.input.amount} ${log.input.symbol} ($${log.input.valueUsd})`);
  logger.info(`   Status: ${log.status}`);
  if (solscanUrl) {
    logger.info(`   Solscan: ${solscanUrl}`);
  }

  return docRef.id;
}

/**
 * Log failed auto-swap attempt
 */
export async function logAutoSwapFailure(
  userId: string,
  delegationId: string,
  input: {token: string; symbol: string; amount: number; valueUsd: number},
  error: string
): Promise<string> {
  const db = getFirestore();

  const docRef = await db.collection("auto_swap_logs").add({
    userId,
    delegationId,
    timestamp: FieldValue.serverTimestamp(),
    input,
    outputs: [],
    status: "failed",
    error,
    totalValueSwapped: 0,
  });

  logger.error(`❌ Auto-swap failure logged: ${docRef.id}`);
  logger.error(`   User: ${userId}`);
  logger.error(`   Error: ${error}`);

  return docRef.id;
}

/**
 * Get auto-swap history for user
 */
export async function getAutoSwapHistory(
  userId: string,
  limit: number = 20
): Promise<AutoSwapLog[]> {
  const db = getFirestore();

  const snapshot = await db
    .collection("auto_swap_logs")
    .where("userId", "==", userId)
    .orderBy("timestamp", "desc")
    .limit(limit)
    .get();

  return snapshot.docs.map(doc => doc.data()) as AutoSwapLog[];
}

/**
 * Get auto-swap stats for user
 */
export async function getAutoSwapStats(userId: string): Promise<{
  totalSwaps: number;
  successfulSwaps: number;
  failedSwaps: number;
  totalVolumeUsd: number;
  last24Hours: {
    swaps: number;
    volumeUsd: number;
  };
}> {
  const db = getFirestore();

  // Get all swaps
  const allSwapsSnapshot = await db
    .collection("auto_swap_logs")
    .where("userId", "==", userId)
    .get();

  const totalSwaps = allSwapsSnapshot.size;
  const successfulSwaps = allSwapsSnapshot.docs.filter(
    doc => doc.data().status === "success"
  ).length;
  const failedSwaps = totalSwaps - successfulSwaps;

  const totalVolumeUsd = allSwapsSnapshot.docs.reduce(
    (sum, doc) => sum + (doc.data().totalValueSwapped || 0),
    0
  );

  // Get last 24 hours
  const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);

  const recentSwapsSnapshot = await db
    .collection("auto_swap_logs")
    .where("userId", "==", userId)
    .where("timestamp", ">=", oneDayAgo)
    .get();

  const last24HoursSwaps = recentSwapsSnapshot.size;
  const last24HoursVolume = recentSwapsSnapshot.docs.reduce(
    (sum, doc) => sum + (doc.data().totalValueSwapped || 0),
    0
  );

  return {
    totalSwaps,
    successfulSwaps,
    failedSwaps,
    totalVolumeUsd,
    last24Hours: {
      swaps: last24HoursSwaps,
      volumeUsd: last24HoursVolume,
    },
  };
}
