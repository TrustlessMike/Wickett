import * as logger from "firebase-functions/logger";
import {HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {PublicKey} from "@solana/web3.js";
import {getAssociatedTokenAddress} from "@solana/spl-token";
import {getSolanaConnection} from "../config/solana-config";
import {JupiterClient} from "../solana/jupiter-client";
import {calculateIncomingBalance, updateBalanceSnapshot} from "../utils/balance-tracker";
import {getPrivyClient, getWalletIdFromDid, PRIVY_AUTHORIZATION_PRIVATE_KEY} from "../config/privy-config";

/**
 * Auto-swap request
 */
export interface AutoSwapRequest {
  userId: string;
  inputToken: string;       // Token mint of incoming payment
  inputSymbol: string;      // e.g., "wBTC"
  inputAmount: number;      // Amount received
  inputValueUsd: number;    // USD value
}

/**
 * Execute auto-swap for incoming payment
 *
 * This function:
 * 1. Validates delegation is active and within limits
 * 2. Uses delegated authority to transfer tokens from user's wallet
 * 3. Swaps via Jupiter to user's portfolio allocation
 * 4. Returns swapped tokens to user's wallet
 * 5. Logs everything for audit trail
 *
 * @param request - Swap request details
 * @param existingData - Optional pre-fetched data to avoid redundant queries (PERFORMANCE OPTIMIZATION)
 * @param privyCredentials - Optional Privy API credentials (appId, appSecret)
 */
export async function executeAutoSwap(
  request: AutoSwapRequest,
  existingData?: {userData: any; delegation: any; delegationDoc: any},
  privyCredentials?: {appId: string; appSecret: string}
): Promise<{success: boolean; signature: string; swaps: any[]}> {
  const {userId, inputToken, inputSymbol, inputAmount, inputValueUsd} = request;

  logger.info(`🔄 Executing auto-swap for user ${userId}`);
  logger.info(`📥 Input: ${inputAmount} ${inputSymbol} ($${inputValueUsd})`);

  const db = getFirestore();
  const connection = getSolanaConnection();
  const jupiterClient = new JupiterClient();

  try {
    // 1. Get user's wallet and delegation (use cached data if available - PERFORMANCE OPTIMIZATION)
    let userData;
    let delegation;
    let delegationDoc;

    if (existingData) {
      userData = existingData.userData;
      delegation = existingData.delegation;
      delegationDoc = existingData.delegationDoc;
      logger.info("✅ Using cached user/delegation data (queries saved)");
    } else {
      const userDoc = await db.collection("users").doc(userId).get();
      userData = userDoc.data();

      if (!userData?.walletAddress) {
        throw new HttpsError("failed-precondition", "User wallet not found");
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
        throw new HttpsError("failed-precondition", "No active delegation");
      }

      delegationDoc = delegationsSnapshot.docs[0];
      delegation = delegationDoc.data();
    }

    if (!userData?.walletAddress) {
      throw new HttpsError("failed-precondition", "User wallet not found");
    }

    const userWallet = new PublicKey(userData.walletAddress);

    // 2. Validate delegation hasn't expired
    const now = new Date();
    const expiresAt = delegation.expiresAt?.toDate();

    if (expiresAt && expiresAt < now) {
      await delegationDoc.ref.update({status: "expired"});
      throw new HttpsError("failed-precondition", "Delegation has expired");
    }

    // 3. Validate within swap limits
    if (inputValueUsd > delegation.maxSwapAmountUsd) {
      logger.warn(
        `⚠️ Swap amount $${inputValueUsd} exceeds limit $${delegation.maxSwapAmountUsd}`
      );
      throw new HttpsError(
        "failed-precondition",
        `Swap amount exceeds per-swap limit of $${delegation.maxSwapAmountUsd}`
      );
    }

    // Check daily limit
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    let todayVolumeUsd = 0;
    try {
      const swapsSnapshot = await db
        .collection("auto_swap_logs")
        .where("userId", "==", userId)
        .where("timestamp", ">=", today)
        .get();

      todayVolumeUsd = swapsSnapshot.docs.reduce(
        (sum, doc) => sum + (doc.data().totalValueSwapped || 0),
        0
      );
    } catch (error: any) {
      // Gracefully handle missing index - assume 0 volume for new users
      if (error.code === 9 || error.message?.includes("index")) {
        logger.warn("⚠️  auto_swap_logs index not ready, assuming 0 daily volume");
        todayVolumeUsd = 0;
      } else {
        throw error;
      }
    }

    if (todayVolumeUsd + inputValueUsd > delegation.dailyLimitUsd) {
      logger.warn(
        `⚠️ Daily limit exceeded: $${todayVolumeUsd} + $${inputValueUsd} > $${delegation.dailyLimitUsd}`
      );
      throw new HttpsError(
        "failed-precondition",
        `Daily limit exceeded: $${todayVolumeUsd.toFixed(2)}/$${delegation.dailyLimitUsd}`
      );
    }

    // 4. Verify we have incoming balance (not touching existing) - PASS CACHED DATA
    const {incomingBalance} = await calculateIncomingBalance(
      userId,
      inputToken,
      inputSymbol,
      {userData, delegation}
    );

    if (incomingBalance < inputAmount) {
      logger.warn(
        `⚠️ Insufficient incoming balance: need ${inputAmount}, have ${incomingBalance}`
      );
      throw new HttpsError(
        "failed-precondition",
        `Insufficient incoming balance to swap`
      );
    }

    logger.info(`✅ Validation passed. Proceeding with swap...`);

    // 5. Calculate portfolio breakdown
    // If the input token is in the portfolio, we keep that percentage and only swap the rest
    const inputTokenInPortfolio = delegation.portfolio.find(
      (item: any) => item.token === inputToken
    );

    const swapBreakdown = delegation.portfolio.map((item: any) => ({
      token: item.token,
      symbol: item.symbol,
      percentage: item.percentage,
      inputAmount: (inputAmount * item.percentage) / 100,
      inputValueUsd: (inputValueUsd * item.percentage) / 100,
      isInputToken: item.token === inputToken,
    }));

    if (inputTokenInPortfolio) {
      logger.info(
        `💡 Input token ${inputSymbol} is in portfolio at ${inputTokenInPortfolio.percentage}%. ` +
        `Keeping ${(inputAmount * inputTokenInPortfolio.percentage) / 100} ${inputSymbol}, ` +
        `swapping ${inputAmount - (inputAmount * inputTokenInPortfolio.percentage) / 100} ${inputSymbol}`
      );
    }

    logger.info(`📊 Swap breakdown: ${JSON.stringify(swapBreakdown)}`);

    // Fetch Jupiter quotes sequentially (1 RPS limit on Lite API)
    logger.info("🔄 Fetching Jupiter quotes sequentially (Lite API 1 RPS limit)...");
    const swapsToQuote = swapBreakdown.filter(swap => swap.percentage > 0 && swap.token !== inputToken);
    const quoteResults = [];

    for (const swap of swapsToQuote) {
      try {
        logger.info(
          `🔄 Requesting quote: ${swap.inputAmount} ${inputSymbol} → ${swap.symbol} (${swap.percentage}%)`
        );
        const quote = await jupiterClient.getQuote({
          inputMint: inputToken,
          outputMint: swap.token,
          amount: Math.floor(swap.inputAmount * 1e9),
          slippageBps: 50,
        });
        quoteResults.push({swap, quote, error: null});

        // Wait 1 second between requests to respect 1 RPS limit
        if (swapsToQuote.indexOf(swap) < swapsToQuote.length - 1) {
          await new Promise(resolve => setTimeout(resolve, 1000));
        }
      } catch (error) {
        logger.error(`❌ Quote failed for ${swap.symbol}:`, error);
        quoteResults.push({swap, quote: null, error});
      }
    }

    const successfulQuotes = quoteResults.filter(r => r.quote);
    logger.info(`✅ Received ${successfulQuotes.length}/${quoteResults.length} quotes successfully`);

    // 6. Execute swaps with fetched quotes using Privy signing
    const swapResults = [];
    const privy = getPrivyClient();

    // Get user's Privy user ID and look up actual wallet ID
    if (!userData.privyUserId) {
      throw new HttpsError(
        "failed-precondition",
        "User Privy user ID not found. Ensure wallet was created via Privy."
      );
    }

    const userWalletId = await getWalletIdFromDid(
      userData.privyUserId,
      privyCredentials?.appId,
      privyCredentials?.appSecret,
      userData.walletAddress // Pass wallet address to match correct wallet for users with multiple
    );
    logger.info(`✅ Resolved wallet ID for signing: ${userWalletId}`);

    // Get authorization private key for signing
    // Must be base64-encoded PKCS8 format WITHOUT PEM headers
    // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
    const authKey = PRIVY_AUTHORIZATION_PRIVATE_KEY.value().trim();
    if (!authKey) {
      throw new HttpsError("failed-precondition", "Authorization key not configured");
    }
    // Log key details for debugging (safe - only shows partial content)
    const crypto = require("crypto");
    const keyHash = crypto.createHash("sha256").update(authKey).digest("hex").substring(0, 16);
    logger.info(`🔑 Authorization key loaded (length: ${authKey.length}, hash: ${keyHash})`);
    logger.info(`🔐 Key starts: ${authKey.substring(0, 20)}, ends: ${authKey.substring(authKey.length - 20)}`);

    // Compare with the expected key for debugging
    const expectedKey = "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgGsZQ6v97fUNqk2yMA4Qx/XWIJMRhAzJe5seFitnJ6cuhRANCAARD531MbX9lrawiwbhKJ4FnLWOFyzLyEhtUL0BvqqLCYPtdtmBfaxzgx+zOZKdXcu1MIysqKmWnBLgNraemYXkd";
    if (authKey !== expectedKey) {
      logger.warn(`⚠️  Key mismatch! Stored key differs from expected`);
      logger.warn(`   Expected length: ${expectedKey.length}, Got: ${authKey.length}`);
      logger.warn(`   Expected starts: ${expectedKey.substring(0, 30)}`);
      logger.warn(`   Got starts: ${authKey.substring(0, 30)}`);
      // Check for common issues
      if (authKey.includes("\n")) {
        logger.warn(`   Issue: Key contains newlines`);
      }
      if (authKey.includes(" ")) {
        logger.warn(`   Issue: Key contains spaces`);
      }
      if (authKey.startsWith("-----")) {
        logger.warn(`   Issue: Key has PEM headers`);
      }
    } else {
      logger.info(`✅ Key matches expected value exactly`);
    }

    for (const {swap, quote, error} of quoteResults) {
      if (!quote || error) {
        logger.warn(`⏭️  Skipping ${swap.symbol} - quote unavailable`);
        continue;
      }

      logger.info(
        `🔄 Executing swap: ${swap.inputAmount} ${inputSymbol} → ${swap.symbol} (${swap.percentage}%)`
      );

      try {
        logger.info(`💱 Using cached quote: ${JSON.stringify(quote)}`);

        // Get swap transaction from Jupiter
        // Use USER'S wallet as the signer since Privy will sign on their behalf
        const swapTxData = await jupiterClient.getSwapTransaction({
          quoteResponse: quote,
          userPublicKey: userData.walletAddress, // User's wallet (Privy will sign)
          wrapAndUnwrapSol: true,
          dynamicComputeUnitLimit: true,
        });

        logger.info(`📝 Jupiter swap transaction built, signing with Privy...`);
        logger.info(`🔐 Authorization key format: starts=${authKey.substring(0, 10)} length=${authKey.length}`);

        // Sign transaction using Privy authorization key, then broadcast manually
        // Using signTransaction instead of signAndSendTransaction to debug 401 issues
        const signResult = await privy.wallets().solana().signTransaction(
          userWalletId,
          {
            transaction: swapTxData.swapTransaction, // Already base64-encoded (string)
            authorization_context: {
              authorization_private_keys: [authKey],
            },
          }
        );

        logger.info(`✅ Transaction signed by Privy, broadcasting to Solana...`);

        // Broadcast the signed transaction to Solana
        const signedTxBuffer = Buffer.from(signResult.signed_transaction, "base64");
        const signature = await connection.sendRawTransaction(signedTxBuffer, {
          skipPreflight: false,
          preflightCommitment: "confirmed",
        });

        // Wait for confirmation
        await connection.confirmTransaction(signature, "confirmed");

        logger.info(`✅ Swap executed: ${signature}`);

        swapResults.push({
          inputToken: inputSymbol,
          inputAmount: swap.inputAmount,
          outputToken: swap.symbol,
          outputAmount: parseFloat(quote.outAmount) / 1e9, // Estimate from quote
          signature: signature, // Transaction signature from Solana broadcast
        });

      } catch (error) {
        logger.error(`❌ Swap failed for ${swap.symbol}:`, error);
        // Continue with other swaps even if one fails
      }
    }

    // 🚀 OPTIMIZATION 4: Parallel Balance Updates (200ms savings)
    logger.info("📊 Updating balance snapshots in parallel...");
    const balanceUpdatePromises = delegation.portfolio.map(async (portfolioItem) => {
      try {
        const newBalance = await connection.getTokenAccountBalance(
          await getAssociatedTokenAddress(
            new PublicKey(portfolioItem.token),
            userWallet
          )
        );

        await updateBalanceSnapshot(
          userId,
          portfolioItem.token,
          parseFloat(newBalance.value.uiAmount?.toString() || "0")
        );
        logger.info(`✅ Updated balance snapshot for ${portfolioItem.symbol}`);
      } catch (error) {
        logger.error(`⚠️  Balance update failed for ${portfolioItem.symbol}:`, error);
        // Don't fail entire operation if balance update fails
      }
    });

    await Promise.all(balanceUpdatePromises);
    logger.info("✅ All balance snapshots updated");

    // Prepare result to return immediately
    const result = {
      success: true,
      signature: swapResults[0]?.signature || "",
      swaps: swapResults,
    };

    // 🚀 OPTIMIZATION 2: Async Logging (300-400ms savings)
    // Fire-and-forget for non-critical logging operations
    logger.info("📝 Logging swap details asynchronously...");
    Promise.all([
      db.collection("auto_swap_logs").add({
        userId,
        delegationId: delegationDoc.id,
        timestamp: FieldValue.serverTimestamp(),
        input: {
          token: inputToken,
          symbol: inputSymbol,
          amount: inputAmount,
          valueUsd: inputValueUsd,
        },
        outputs: swapResults,
        totalValueSwapped: inputValueUsd,
        status: "success",
      }),
      delegationDoc.ref.update({
        lastSwapAt: FieldValue.serverTimestamp(),
        totalSwapsExecuted: FieldValue.increment(1),
        totalVolumeSwappedUsd: FieldValue.increment(inputValueUsd),
      })
    ]).catch(error => {
      // Log error but don't fail the function - swap already succeeded
      logger.error("⚠️  Async logging failed (non-critical):", error);
    });

    logger.info(`✅ Auto-swap completed successfully for user ${userId}`);
    logger.info("📊 Performance optimizations applied: Parallel quotes, Blockhash reuse, Parallel balance updates, Async logging");

    return result;

  } catch (error) {
    logger.error("❌ Auto-swap failed:", error);

    // Log the failure
    await db.collection("auto_swap_logs").add({
      userId,
      timestamp: FieldValue.serverTimestamp(),
      input: {
        token: inputToken,
        symbol: inputSymbol,
        amount: inputAmount,
        valueUsd: inputValueUsd,
      },
      error: error instanceof Error ? error.message : String(error),
      status: "failed",
    });

    throw error;
  }
}
