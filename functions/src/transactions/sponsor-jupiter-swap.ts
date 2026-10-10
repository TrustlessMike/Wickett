import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { PublicKey } from "@solana/web3.js";
import * as logger from "firebase-functions/logger";
import {
  HELIUS_RPC_URL,
  SOLANA_FEE_PAYER_PRIVATE_KEY,
  getFeePayerPublicKey,
  getSolanaConnection,
  PLATFORM_FEES,
  PLATFORM_FEE_WALLET,
  JUPITER_REFERRAL_ACCOUNT,
} from "../config/solana-config";
import {
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
import { JupiterClient, JUPITER_API_KEY } from "../solana/jupiter-client";

interface SponsorJupiterSwapRequest {
  inputMint: string; // Token mint to swap FROM
  outputMint: string; // Token mint to swap TO
  amount: number; // Amount in smallest unit (lamports/tokens)
  slippageBps?: number; // Slippage tolerance in basis points (default: 50 = 0.5%)
  userWalletAddress?: string; // Optional - will get from Firestore if not provided
}

interface SponsorJupiterSwapResponse {
  success: boolean;
  partiallySignedTransaction?: string; // base64
  estimatedFee?: number;
  quote?: {
    inputMint: string;
    outputMint: string;
    inAmount: string;
    outAmount: string;
    priceImpactPct: string;
    slippageBps: number;
  };
  error?: string;
  code?: string;
}

/**
 * Sponsor a Jupiter swap transaction - V2 with user signing
 *
 * Flow:
 * 1. Get quote from Jupiter API
 * 2. Backend builds swap transaction
 * 3. Backend signs with fee payer (for gas sponsorship)
 * 4. Returns partially-signed transaction to client
 * 5. Client gets user signature via Privy
 * 6. Client calls broadcastSignedTransaction to submit
 */
export const sponsorJupiterSwap = onCall<
  SponsorJupiterSwapRequest,
  Promise<SponsorJupiterSwapResponse>
>(
  {
    secrets: [HELIUS_RPC_URL, SOLANA_FEE_PAYER_PRIVATE_KEY, JUPITER_API_KEY],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (
    request: CallableRequest<SponsorJupiterSwapRequest>
  ): Promise<SponsorJupiterSwapResponse> => {
    const { inputMint, outputMint, amount, slippageBps, userWalletAddress } = request.data;

    try {
      logger.info("🚀 [Jupiter Swap] Starting sponsored swap transaction build");
      logger.info(`Swap: ${inputMint} -> ${outputMint}`);
      logger.info(`Amount: ${amount}`);
      logger.info(`Slippage: ${slippageBps || 50} bps (${(slippageBps || 50) / 100}%)`);

      // Validate mint addresses
      if (!isValidSolanaAddress(inputMint)) {
        return createErrorResponse(
          "INVALID_INPUT_MINT",
          "Invalid input token mint address"
        ) as SponsorJupiterSwapResponse;
      }

      if (!isValidSolanaAddress(outputMint)) {
        return createErrorResponse(
          "INVALID_OUTPUT_MINT",
          "Invalid output token mint address"
        ) as SponsorJupiterSwapResponse;
      }

      // Validate amount
      if (!amount || amount <= 0) {
        return createErrorResponse(
          "INVALID_AMOUNT",
          "Amount must be greater than 0"
        ) as SponsorJupiterSwapResponse;
      }

      // Perform security checks (auth, rate limiting, amount validation, logging)
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

        // Initialize Jupiter client
        const jupiterClient = new JupiterClient();

        // Step 1: Get quote from Jupiter with platform fee
        logger.info("📊 Fetching quote from Jupiter...");
        logger.info(`💰 Platform fee: ${PLATFORM_FEES.SWAP_FEE_BPS} bps (${PLATFORM_FEES.SWAP_FEE_BPS / 100}%)`);
        const quote = await jupiterClient.getQuote({
          inputMint,
          outputMint,
          amount,
          slippageBps: slippageBps || 50,
          platformFeeBps: PLATFORM_FEES.SWAP_FEE_BPS,
        });

        logger.info(`✅ Quote received:`);
        logger.info(`   Input: ${quote.inAmount}`);
        logger.info(`   Output: ${quote.outAmount}`);
        logger.info(`   Price Impact: ${quote.priceImpactPct}%`);
        logger.info(`   Route: ${quote.routePlan.length} step(s)`);

        // Step 2: Get swap transaction from Jupiter with referral fee (Ultra API)
        logger.info("🔨 Building swap transaction...");
        logger.info(`💳 Fee collection wallet: ${PLATFORM_FEE_WALLET}`);

        // Build swap params with referral fee if configured
        const swapParams: any = {
          quoteResponse: quote,
          userPublicKey: userWalletFromRequest,
          wrapAndUnwrapSol: true,
          dynamicComputeUnitLimit: true,
        };

        // Add referral fee params for Ultra API fee collection
        if (JUPITER_REFERRAL_ACCOUNT) {
          swapParams.referralAccount = JUPITER_REFERRAL_ACCOUNT;
          swapParams.referralFeeBps = PLATFORM_FEES.SWAP_FEE_BPS;
          logger.info(`💰 Referral account: ${JUPITER_REFERRAL_ACCOUNT}`);
          logger.info(`💰 Referral fee: ${PLATFORM_FEES.SWAP_FEE_BPS} bps`);
        } else {
          logger.warn("⚠️ JUPITER_REFERRAL_ACCOUNT not configured - fees will not be collected");
        }

        const swap = await jupiterClient.getSwapTransaction(swapParams);

        logger.info("✅ Swap transaction built by Jupiter");

        // Step 3: Deserialize the transaction
        logger.info("📦 Deserializing swap transaction...");
        const transaction = jupiterClient.deserializeSwapTransaction(swap.swapTransaction);

        logger.info("✅ Transaction deserialized");

        // Step 4: Modify fee payer to backend wallet
        // Jupiter returns transaction with user as fee payer, we need to change it
        transaction.message.staticAccountKeys[0] = getFeePayerPublicKey();

        logger.info("✅ Fee payer updated to backend wallet");

        // Step 5: Simulate transaction
        logger.info("🔍 Simulating swap transaction...");
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
            `Swap simulation failed: ${simulation.error}`,
            { logs: simulation.logs }
          ) as SponsorJupiterSwapResponse;
        }

        logger.info("✅ Simulation successful");

        // Step 6: Sign transaction with fee payer ONLY
        // User will sign on client side before broadcast
        signTransactionWithFeePayer(transaction);

        logger.info("✅ Transaction signed with fee payer (partial signature)");

        // Step 7: Estimate fee for informational purposes
        const estimatedFee = await estimateTransactionFee(transaction);

        // Step 8: Serialize to base64 for client
        const partiallySignedTx = serializeTransaction(transaction);

        logger.info("✅ Partially-signed swap transaction ready for client");
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
            quote: {
              inputMint: quote.inputMint,
              outputMint: quote.outputMint,
              inAmount: quote.inAmount,
              outAmount: quote.outAmount,
              priceImpactPct: quote.priceImpactPct,
              slippageBps: quote.slippageBps,
            },
          },
          "Swap transaction built successfully. Ready for user signature."
        ) as SponsorJupiterSwapResponse;
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
      logger.error("❌ [Jupiter Swap] Sponsored swap build failed:", error);

      if (error instanceof HttpsError) {
        throw error;
      }

      return createErrorResponse(
        "SWAP_BUILD_FAILED",
        error instanceof Error ? error.message : "Failed to build swap transaction",
        { error }
      ) as SponsorJupiterSwapResponse;
    }
  }
);
