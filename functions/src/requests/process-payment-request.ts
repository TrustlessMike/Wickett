import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { jupiterClient, JUPITER_API_KEY } from "../solana/jupiter-client";
import { Connection, PublicKey, VersionedTransaction } from "@solana/web3.js";
import { getSolanaConnection } from "../config/solana-config";

interface ConversionStep {
  fromToken: string;
  toToken: string;
  inputAmount: number;
  outputAmount: number;
  fiatValue?: number;
  priceImpact: number;
  route: string[];
}

interface ProcessPaymentData {
  requestId: string;
  paymentToken: string;
  breakdown: ConversionStep[];
}

/**
 * Cloud Function: processPaymentRequest
 * Processes a payment request with multi-hop token swaps
 */
export const processPaymentRequest = onCall(
  {
    secrets: [JUPITER_API_KEY],
    invoker: "public",
  },
  async (request) => {
    const { auth, data } = request;

    // Verify authentication
    if (!auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = auth.uid;
    const { requestId, paymentToken, breakdown } = data as ProcessPaymentData;

    // Validate input
    if (!requestId || typeof requestId !== "string") {
      throw new HttpsError("invalid-argument", "requestId is required");
    }

    if (!paymentToken || typeof paymentToken !== "string") {
      throw new HttpsError("invalid-argument", "paymentToken is required");
    }

    if (!Array.isArray(breakdown) || breakdown.length === 0) {
      throw new HttpsError("invalid-argument", "breakdown is required");
    }

    try {
      const db = getFirestore();

      // Get payment request
      const requestDoc = await db.collection("payment_requests").doc(requestId).get();
      if (!requestDoc.exists) {
        throw new HttpsError("not-found", "Payment request not found");
      }

      const paymentRequest = requestDoc.data()!;

      // Verify request is still pending
      if (paymentRequest.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          `Request is no longer pending (status: ${paymentRequest.status})`
        );
      }

      // Get payer's wallet address
      const userDoc = await db.collection("users").doc(userId).get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User not found");
      }

      const userData = userDoc.data()!;
      const payerAddress = userData.walletAddress;

      if (!payerAddress) {
        throw new HttpsError("failed-precondition", "User does not have a wallet address");
      }

      logger.info(
        `Processing payment for request ${requestId}: ${paymentToken} → multi-token portfolio`
      );

      // Execute each conversion step
      const transactions: any[] = [];
      const connection = getSolanaConnection();

      for (const step of breakdown) {
        logger.info(`Executing swap: ${step.fromToken} → ${step.toToken}`);

        // Get token mints (this should be looked up from a registry)
        const inputMint = getTokenMint(step.fromToken);
        const outputMint = getTokenMint(step.toToken);

        // Convert amounts to lamports
        const inputAmountLamports = Math.floor(
          step.inputAmount * Math.pow(10, getTokenDecimals(inputMint))
        );

        // Get quote from Jupiter
        const quote = await jupiterClient.getQuote({
          inputMint,
          outputMint,
          amount: inputAmountLamports,
          slippageBps: 50,
        });

        // Get swap transaction
        const swap = await jupiterClient.getSwapTransaction({
          quoteResponse: quote,
          userPublicKey: payerAddress,
        });

        transactions.push({
          id: `tx-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
          token: step.toToken,
          amount: step.outputAmount,
          fiatValue: step.fiatValue || 0,
          swapTransaction: swap.swapTransaction,
        });

        logger.info(`✅ Swap transaction prepared for ${step.toToken}`);
      }

      // Note: In production, these transactions would be signed by the user
      // and submitted to the blockchain. For now, we return them for client-side signing.

      // Update payment request status to "paid" (optimistically)
      // In reality, this should wait for blockchain confirmation
      const now = Timestamp.now();
      await requestDoc.ref.update({
        status: "paid",
        paidBy: userId,
        paidAt: now,
        paymentToken,
        paymentCount: (paymentRequest.paymentCount || 0) + 1,
        lastPaidAt: now,
      });

      logger.info(`✅ Payment request ${requestId} marked as paid`);

      return {
        success: true,
        data: {
          transactions,
          message: "Payment processed successfully. Sign and submit transactions to complete.",
        },
      };
    } catch (error: any) {
      logger.error("❌ Error processing payment request:", error);
      throw new HttpsError("internal", `Failed to process payment: ${error.message}`);
    }
  }
);

/**
 * Get token mint address from symbol
 * TODO: This should use a proper token registry
 */
function getTokenMint(symbol: string): string {
  const mints: Record<string, string> = {
    SOL: "So11111111111111111111111111111111111111112",
    USDC: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",
    ZEC: "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS",
    BONK: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263",
    wBTC: "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh",
    wETH: "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs",
    JUP: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
    RAY: "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R",
    GOLD: "GoLDppdjB1vDTPSGxyMJFqdnj134yH6Prg9eqsGDiw6A",
    AAPLx: "XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp",
    TSLAx: "XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB",
    NVDAx: "Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh",
    MSFTx: "XspzcW1PRtgf6Wj92HCiZdjzKCyFekVD8P5Ueh3dRMX",
    AMZNx: "Xs3eBt7uRfJX8QUs4suhyU8p2M6DoUDrJyWBa8LLZsg",
  };

  const mint = mints[symbol];
  if (!mint) {
    throw new Error(`Unknown token symbol: ${symbol}`);
  }

  return mint;
}

/**
 * Get token decimals
 */
function getTokenDecimals(mint: string): number {
  // SOL
  if (mint === "So11111111111111111111111111111111111111112") {
    return 9;
  }

  // USDC, USDT, JUP, RAY
  if (
    mint === "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" ||
    mint === "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB" ||
    mint === "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN" ||
    mint === "4k3Dyjzvzp8eMZWUXbBCjEvwSkkk59S5iCNLY3QrkX6R"
  ) {
    return 6;
  }

  // wBTC, wETH, ZEC, xStocks
  if (
    mint === "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh" ||
    mint === "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs" ||
    mint === "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS" ||
    mint.startsWith("Xs")
  ) {
    return 8;
  }

  // BONK
  if (mint === "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263") {
    return 5;
  }

  // Default to 9
  return 9;
}
