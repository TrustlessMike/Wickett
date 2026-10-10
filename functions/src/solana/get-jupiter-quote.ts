import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { jupiterClient, JUPITER_API_KEY } from "./jupiter-client";
import axios from "axios";

interface GetJupiterQuoteData {
  inputMint: string;
  outputMint: string;
  amount: number;
  isFiatAmount?: boolean;
  fiatCurrency?: string;
  slippageBps?: number;
}

/**
 * Cloud Function: getJupiterQuote
 * Gets a quote for token swap, optionally converting from fiat amount
 */
export const getJupiterQuote = onCall(
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

    const {
      inputMint,
      outputMint,
      amount,
      isFiatAmount = false,
      fiatCurrency = "USD",
      slippageBps = 50,
    } = data as GetJupiterQuoteData;

    // Validate input
    if (!inputMint || typeof inputMint !== "string") {
      throw new HttpsError("invalid-argument", "inputMint is required");
    }

    if (!outputMint || typeof outputMint !== "string") {
      throw new HttpsError("invalid-argument", "outputMint is required");
    }

    if (!amount || amount <= 0) {
      throw new HttpsError("invalid-argument", "amount must be greater than 0");
    }

    try {
      let inputAmountLamports: number;

      if (isFiatAmount) {
        // Convert fiat amount to input token amount
        logger.info(`Converting ${amount} ${fiatCurrency} to ${inputMint} amount`);

        // Get token prices in USD
        const inputPrice = await getTokenPriceUSD(inputMint);
        const outputPrice = await getTokenPriceUSD(outputMint);

        if (!inputPrice || !outputPrice) {
          throw new Error("Failed to fetch token prices");
        }

        // Convert fiat to input token amount
        // For example: $100 / $50 per token = 2 tokens
        const inputTokenAmount = amount / inputPrice;

        // Convert to lamports (smallest unit)
        // Assuming 9 decimals for SOL, 6 for most SPL tokens
        // This should be looked up per token, but using 9 as default for now
        const decimals = getTokenDecimals(inputMint);
        inputAmountLamports = Math.floor(inputTokenAmount * Math.pow(10, decimals));

        logger.info(
          `Converted ${amount} ${fiatCurrency} to ${inputTokenAmount} tokens (${inputAmountLamports} lamports)`
        );
      } else {
        // Amount is already in lamports
        inputAmountLamports = amount;
      }

      // Get quote from Jupiter
      const quote = await jupiterClient.getQuote({
        inputMint,
        outputMint,
        amount: inputAmountLamports,
        slippageBps,
      });

      // Calculate human-readable amounts
      const inputDecimals = getTokenDecimals(inputMint);
      const outputDecimals = getTokenDecimals(outputMint);

      const inputAmount = parseInt(quote.inAmount) / Math.pow(10, inputDecimals);
      const outputAmount = parseInt(quote.outAmount) / Math.pow(10, outputDecimals);

      // Extract route plan (simplified)
      const routePlan = quote.routePlan.map((step) => step.swapInfo.label);

      logger.info(`✅ Quote fetched: ${inputAmount} → ${outputAmount}`);

      return {
        success: true,
        data: {
          inputAmount,
          outputAmount,
          priceImpact: parseFloat(quote.priceImpactPct),
          routePlan,
          estimatedFee: quote.routePlan.reduce(
            (sum, step) => sum + parseInt(step.swapInfo.feeAmount),
            0
          ),
          quote: quote, // Include full quote for potential swap execution
        },
      };
    } catch (error: any) {
      logger.error("❌ Error getting Jupiter quote:", error);
      throw new HttpsError("internal", `Failed to get quote: ${error.message}`);
    }
  }
);

/**
 * Get token price in USD from Jupiter Price API
 */
async function getTokenPriceUSD(mint: string): Promise<number | null> {
  try {
    const response = await axios.get("https://price.jup.ag/v4/price", {
      params: { ids: mint },
    });

    const responseData = (response as any).data;
    const priceData = responseData.data[mint];
    if (!priceData) {
      logger.info(`Price not found for token: ${mint}`);
      return null;
    }

    return priceData.price;
  } catch (error) {
    logger.error(`Failed to get price for ${mint}:`, error);
    return null;
  }
}

/**
 * Get token decimals (hardcoded for now, should be looked up dynamically)
 */
function getTokenDecimals(mint: string): number {
  // SOL
  if (mint === "So11111111111111111111111111111111111111112") {
    return 9;
  }

  // USDC, USDT
  if (
    mint === "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" ||
    mint === "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"
  ) {
    return 6;
  }

  // wBTC, wETH
  if (
    mint === "3NZ9JMVBmGAqocybic2c7LQCJScmgsAZ6vQqTDzcqmJh" ||
    mint === "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs"
  ) {
    return 8;
  }

  // Default to 9 decimals for unknown tokens
  return 9;
}
