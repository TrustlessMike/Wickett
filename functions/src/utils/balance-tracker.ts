import * as logger from "firebase-functions/logger";
import {getFirestore} from "firebase-admin/firestore";
import {PublicKey} from "@solana/web3.js";
import {getAssociatedTokenAddress} from "@solana/spl-token";
import {getSolanaConnection} from "../config/solana-config";

/**
 * Balance tracking utility
 *
 * Tracks user token balances to differentiate between:
 * - Existing balance (locked, can't auto-swap)
 * - Incoming balance (new, can auto-swap)
 */

export interface TokenBalance {
  tokenMint: string;
  symbol: string;
  existingBalance: number;     // Balance when delegation was enabled
  currentBalance: number;       // Current on-chain balance
  incomingBalance: number;      // New tokens received since delegation
  lastChecked: FirebaseFirestore.Timestamp;
}

/**
 * Get current on-chain token balance
 */
export async function getCurrentTokenBalance(
  walletAddress: string,
  tokenMint: string
): Promise<number> {
  try {
    const connection = getSolanaConnection();
    const wallet = new PublicKey(walletAddress);

    // SOL is a native balance, not a token account
    if (tokenMint === "So11111111111111111111111111111111111111112") {
      const balance = await connection.getBalance(wallet);
      return balance / 1e9; // Convert lamports to SOL
    }

    // For SPL tokens, use token account
    const mint = new PublicKey(tokenMint);
    const tokenAccount = await getAssociatedTokenAddress(mint, wallet);
    const balance = await connection.getTokenAccountBalance(tokenAccount);

    return parseFloat(balance.value.uiAmount?.toString() || "0");
  } catch (error) {
    // Token account doesn't exist or other error
    logger.warn(`⚠️ Could not get balance for ${tokenMint}: ${error}`);
    return 0;
  }
}

/**
 * Calculate incoming balance (new tokens received since delegation)
 *
 * @param userId - User ID
 * @param tokenMint - Token mint address
 * @param symbol - Token symbol
 * @param existingData - Optional pre-fetched user and delegation data to avoid redundant queries
 */
export async function calculateIncomingBalance(
  userId: string,
  tokenMint: string,
  symbol: string,
  existingData?: {userData: any; delegation: any}
): Promise<{existingBalance: number; currentBalance: number; incomingBalance: number}> {
  const db = getFirestore();

  let userData;
  let delegation;

  if (existingData) {
    userData = existingData.userData;
    delegation = existingData.delegation;
    logger.info("✅ Using cached user/delegation data (queries saved)");
  } else {
    // Get user's wallet
    const userDoc = await db.collection("users").doc(userId).get();
    userData = userDoc.data();

    if (!userData?.walletAddress) {
      throw new Error("User wallet not found");
    }

    // Get active delegation
    const delegationsSnapshot = await db
      .collection("users")
      .doc(userId)
      .collection("delegations")
      .where("status", "==", "active")
      .limit(1)
      .get();

    if (delegationsSnapshot.empty) {
      throw new Error("No active delegation found");
    }

    delegation = delegationsSnapshot.docs[0].data();
  }

  if (!userData?.walletAddress) {
    throw new Error("User wallet not found");
  }

  const existingBalance = delegation.balanceSnapshots?.[tokenMint] || 0;

  // Get current on-chain balance
  const currentBalance = await getCurrentTokenBalance(
    userData.walletAddress,
    tokenMint
  );

  // Calculate incoming balance
  // If current > existing, we have new tokens
  const incomingBalance = Math.max(0, currentBalance - existingBalance);

  logger.info(`📊 Balance calculation for ${symbol}:`);
  logger.info(`   Existing (locked): ${existingBalance}`);
  logger.info(`   Current (on-chain): ${currentBalance}`);
  logger.info(`   Incoming (swappable): ${incomingBalance}`);

  return {
    existingBalance,
    currentBalance,
    incomingBalance,
  };
}

/**
 * Update balance snapshot after swap
 */
export async function updateBalanceSnapshot(
  userId: string,
  tokenMint: string,
  newBalance: number
): Promise<void> {
  const db = getFirestore();

  // Get active delegation
  const delegationsSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("delegations")
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (delegationsSnapshot.empty) {
    throw new Error("No active delegation found");
  }

  const delegationDoc = delegationsSnapshot.docs[0];

  // Update balance snapshot
  await delegationDoc.ref.update({
    [`balanceSnapshots.${tokenMint}`]: newBalance,
  });

  logger.info(`📊 Updated balance snapshot for ${tokenMint}: ${newBalance}`);
}

/**
 * Check if user has enough incoming balance to swap
 */
export async function hasEnoughIncomingBalance(
  userId: string,
  tokenMint: string,
  symbol: string,
  requiredAmount: number
): Promise<boolean> {
  const {incomingBalance} = await calculateIncomingBalance(userId, tokenMint, symbol);

  const hasEnough = incomingBalance >= requiredAmount;

  if (!hasEnough) {
    logger.warn(
      `⚠️ Insufficient incoming balance for ${symbol}: ` +
      `need ${requiredAmount}, have ${incomingBalance}`
    );
  }

  return hasEnough;
}

/**
 * Get all token balances for user
 */
export async function getAllTokenBalances(
  userId: string
): Promise<Map<string, TokenBalance>> {
  const db = getFirestore();
  const balances = new Map<string, TokenBalance>();

  // Get active delegation
  const delegationsSnapshot = await db
    .collection("users")
    .doc(userId)
    .collection("delegations")
    .where("status", "==", "active")
    .limit(1)
    .get();

  if (delegationsSnapshot.empty) {
    return balances;
  }

  const delegation = delegationsSnapshot.docs[0].data();
  const userDoc = await db.collection("users").doc(userId).get();
  const userData = userDoc.data();

  if (!userData?.walletAddress) {
    return balances;
  }

  // Get balances for all portfolio tokens
  for (const portfolioItem of delegation.portfolio) {
    const {existingBalance, currentBalance, incomingBalance} =
      await calculateIncomingBalance(
        userId,
        portfolioItem.token,
        portfolioItem.symbol
      );

    balances.set(portfolioItem.token, {
      tokenMint: portfolioItem.token,
      symbol: portfolioItem.symbol,
      existingBalance,
      currentBalance,
      incomingBalance,
      lastChecked: new Date() as any,
    });
  }

  return balances;
}
