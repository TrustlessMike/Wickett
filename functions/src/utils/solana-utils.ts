import { PublicKey } from "@solana/web3.js";
import * as logger from "firebase-functions/logger";

/**
 * Validate Solana address
 */
export function isValidSolanaAddress(address: string): boolean {
  try {
    new PublicKey(address);
    return true;
  } catch {
    return false;
  }
}

/**
 * Create error response with logging
 */
export function createErrorResponse(
  errorCode: string,
  message: string,
  details?: unknown
): { success: false; error: string; code: string; details?: unknown } {
  logger.error(`[${errorCode}] ${message}`, details);
  return {
    success: false,
    error: message,
    code: errorCode,
    ...(details && { details }),
  };
}

/**
 * Create success response with logging
 */
export function createSuccessResponse<T>(
  data: T,
  message?: string
): { success: true; data: T; message?: string } {
  if (message) {
    logger.info(`✅ ${message}`);
  }

  const response: { success: true; data: T; message?: string } = {
    success: true,
    data,
  };

  if (message) {
    response.message = message;
  }

  return response;
}

/**
 * Sleep utility for retries
 */
export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Retry with exponential backoff
 */
export async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxRetries: number = 3,
  baseDelay: number = 1000
): Promise<T> {
  let lastError: Error | undefined;

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      if (i < maxRetries - 1) {
        const delay = baseDelay * Math.pow(2, i);
        logger.warn(`Retry attempt ${i + 1} after ${delay}ms:`, lastError.message);
        await sleep(delay);
      }
    }
  }

  throw lastError;
}

/**
 * Convert lamports to SOL
 */
export function lamportsToSol(lamports: number): number {
  return lamports / 1e9;
}

/**
 * Convert SOL to lamports
 */
export function solToLamports(sol: number): number {
  return Math.floor(sol * 1e9);
}
