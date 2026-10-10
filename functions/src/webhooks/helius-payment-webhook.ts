import * as logger from "firebase-functions/logger";
import {onRequest} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {executeAutoSwap} from "../auto-convert/execute-auto-swap";
import {validateDelegation} from "../middleware/delegation-validator";
import {
  SOLANA_FEE_PAYER_PRIVATE_KEY,
  HELIUS_RPC_URL,
  HELIUS_API_KEY,
} from "../config/solana-config";
import {PRIVY_APP_ID, PRIVY_APP_SECRET, PRIVY_AUTHORIZATION_PRIVATE_KEY} from "../config/privy-config";
import {jupiterClient, JUPITER_API_KEY} from "../solana/jupiter-client";

/**
 * Helius webhook payload for token transfers
 */
interface HeliusWebhookPayload {
  type: string;
  source: string;
  nativeTransfers?: Array<{
    fromUserAccount: string;
    toUserAccount: string;
    amount: number;
  }>;
  tokenTransfers?: Array<{
    fromUserAccount: string;
    toUserAccount: string;
    mint: string;
    tokenAmount: number;
    tokenStandard: string;
  }>;
  signature: string;
  timestamp: number;
}

/**
 * Helius Webhook Handler
 *
 * Listens for incoming token transfers and triggers auto-swap if:
 * 1. User has active delegation
 * 2. Transfer is TO user's wallet (not FROM)
 * 3. Delegation limits are not exceeded
 */
export const heliusPaymentWebhook = onRequest(
  {
    secrets: [SOLANA_FEE_PAYER_PRIVATE_KEY, HELIUS_RPC_URL, HELIUS_API_KEY, PRIVY_APP_ID, PRIVY_APP_SECRET, PRIVY_AUTHORIZATION_PRIVATE_KEY, JUPITER_API_KEY],
  },
  async (request, response) => {
  logger.info("📥 Helius webhook received");

  try {
    const payload = request.body as HeliusWebhookPayload[];

    if (!Array.isArray(payload)) {
      logger.warn("⚠️ Invalid webhook payload format");
      response.status(400).send("Invalid payload");
      return;
    }

    const db = getFirestore();

    // Process each transaction
    for (const transaction of payload) {
      logger.info(`🔍 Processing transaction: ${transaction.signature}`);
      logger.info(`   Type: ${transaction.type}`);

      // Only process token transfers
      if (transaction.type !== "TRANSFER") {
        logger.info("⏭️  Skipping non-transfer transaction");
        continue;
      }

      // Check token transfers
      if (transaction.tokenTransfers) {
        for (const transfer of transaction.tokenTransfers) {
          logger.info(`💸 Token transfer detected:`);
          logger.info(`   From: ${transfer.fromUserAccount}`);
          logger.info(`   To: ${transfer.toUserAccount}`);
          logger.info(`   Mint: ${transfer.mint}`);
          logger.info(`   Amount: ${transfer.tokenAmount}`);

          // Find user by wallet address (recipient)
          const usersSnapshot = await db
            .collection("users")
            .where("walletAddress", "==", transfer.toUserAccount)
            .limit(1)
            .get();

          if (usersSnapshot.empty) {
            logger.info("⏭️  Recipient not found in database");
            continue;
          }

          const userDoc = usersSnapshot.docs[0];
          const userId = userDoc.id;

          logger.info(`👤 Recipient found: ${userId}`);

          // Check if user has active delegation
          const delegationsSnapshot = await db
            .collection("users")
            .doc(userId)
            .collection("delegations")
            .where("status", "==", "active")
            .limit(1)
            .get();

          if (delegationsSnapshot.empty) {
            logger.info("⏭️  User has no active delegation. Auto-swap disabled.");
            continue;
          }

          const delegationDoc = delegationsSnapshot.docs[0];
          const delegation = delegationDoc.data();
          const userData = userDoc.data();

          logger.info("✅ User has active delegation. Checking limits...");

          // TODO: Get USD value of transfer (need price oracle)
          // For now, estimate based on token mint
          const transferValueUsd = await estimateTokenValue(
            transfer.mint,
            transfer.tokenAmount
          );

          logger.info(`💰 Estimated value: $${transferValueUsd}`);

          // Validate delegation and limits (pass existing data to avoid re-querying)
          const validation = await validateDelegation(
            userId,
            transferValueUsd,
            {delegation, delegationDoc}
          );

          if (!validation.isValid) {
            logger.warn(`⚠️ Delegation validation failed: ${validation.reason}`);
            continue;
          }

          logger.info("✅ Delegation validated. Triggering auto-swap...");

          // Trigger auto-swap (pass existing data to avoid re-querying)
          try {
            const result = await executeAutoSwap(
              {
                userId,
                inputToken: transfer.mint,
                inputSymbol: await getTokenSymbol(transfer.mint),
                inputAmount: transfer.tokenAmount,
                inputValueUsd: transferValueUsd,
              },
              {userData, delegation, delegationDoc},
              {appId: PRIVY_APP_ID.value().trim(), appSecret: PRIVY_APP_SECRET.value().trim()}
            );

            logger.info(`✅ Auto-swap completed: ${result.signature}`);
            logger.info(`   Swaps: ${JSON.stringify(result.swaps)}`);

            // TODO: Send push notification to user
            // "Received $X in TOKEN, converted to your portfolio"

          } catch (error) {
            logger.error(`❌ Auto-swap failed: ${error}`);
            // Error is already logged in executeAutoSwap
          }
        }
      }

      // Check SOL transfers
      if (transaction.nativeTransfers) {
        for (const transfer of transaction.nativeTransfers) {
          logger.info(`💸 SOL transfer detected:`);
          logger.info(`   From: ${transfer.fromUserAccount}`);
          logger.info(`   To: ${transfer.toUserAccount}`);
          logger.info(`   Amount: ${transfer.amount / 1e9} SOL`);

          // Similar logic as token transfers
          // Find user by wallet address
          const usersSnapshot = await db
            .collection("users")
            .where("walletAddress", "==", transfer.toUserAccount)
            .limit(1)
            .get();

          if (usersSnapshot.empty) {
            logger.info("⏭️  Recipient not found in database");
            continue;
          }

          const userDoc = usersSnapshot.docs[0];
          const userId = userDoc.id;

          // Check delegation
          const delegationsSnapshot = await db
            .collection("users")
            .doc(userId)
            .collection("delegations")
            .where("status", "==", "active")
            .limit(1)
            .get();

          if (delegationsSnapshot.empty) {
            logger.info("⏭️  User has no active delegation");
            continue;
          }

          const delegationDoc = delegationsSnapshot.docs[0];
          const delegation = delegationDoc.data();
          const userData = userDoc.data();

          // Always trigger auto-swap regardless of whether SOL is in portfolio
          // The executeAutoSwap function will handle keeping the right percentage
          const solValueUsd = await estimateTokenValue(
            "So11111111111111111111111111111111111111112", // SOL mint
            transfer.amount / 1e9  // Convert lamports to SOL
          );

          const validation = await validateDelegation(
            userId,
            solValueUsd,
            {delegation, delegationDoc}
          );

          if (!validation.isValid) {
            logger.warn(`⚠️ Delegation validation failed: ${validation.reason}`);
            continue;
          }

          logger.info("✅ Triggering SOL auto-swap...");

          try {
            const result = await executeAutoSwap(
              {
                userId,
                inputToken: "So11111111111111111111111111111111111111112",
                inputSymbol: "SOL",
                inputAmount: transfer.amount / 1e9,  // Convert lamports to SOL
                inputValueUsd: solValueUsd,
              },
              {userData, delegation, delegationDoc},
              {appId: PRIVY_APP_ID.value().trim(), appSecret: PRIVY_APP_SECRET.value().trim()}
            );

            logger.info(`✅ SOL auto-swap completed: ${result.signature}`);

          } catch (error) {
            logger.error(`❌ SOL auto-swap failed: ${error}`);
          }
        }
      }
    }

    response.status(200).send("OK");

  } catch (error) {
    logger.error("❌ Webhook processing failed:", error);
    response.status(500).send("Internal error");
  }
  }
);

/**
 * Estimate USD value of token amount using Jupiter Price API
 */
async function estimateTokenValue(
  tokenMint: string,
  amount: number
): Promise<number> {
  try {
    const {price} = await jupiterClient.getTokenPrice(tokenMint);
    return amount * price;
  } catch (error) {
    logger.warn(`⚠️ Failed to get price for ${tokenMint}, using $1 fallback`);
    return amount * 1;
  }
}

/**
 * Get token symbol from mint address
 * TODO: Maintain token registry or use on-chain metadata
 */
async function getTokenSymbol(tokenMint: string): Promise<string> {
  const mockSymbols: {[key: string]: string} = {
    "So11111111111111111111111111111111111111112": "SOL",
    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": "USDC",
    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": "USDT",
    "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263": "BONK",
  };

  return mockSymbols[tokenMint] || "UNKNOWN";
}
