import {PrivyClient} from "@privy-io/node";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

/**
 * Privy Configuration
 */

// Secrets
export const PRIVY_APP_ID = defineSecret("PRIVY_APP_ID");
export const PRIVY_APP_SECRET = defineSecret("PRIVY_APP_SECRET");
export const PRIVY_AUTHORIZATION_PRIVATE_KEY = defineSecret("PRIVY_AUTHORIZATION_PRIVATE_KEY");
export const PRIVY_PREDICTION_AUTH_KEY = defineSecret("PRIVY_PREDICTION_AUTH_KEY");

// Quorum IDs for different authorization keys
export const PREDICTION_KEY_QUORUM_ID = "t5czqmtdq7qmmgg5taxl3nfx";

/**
 * Initialize Privy Client for server-side wallet actions
 *
 * IMPORTANT: Sets PRIVY_AUTHORIZATION_PRIVATE_KEY as environment variable
 * before creating client, as Privy SDK reads it internally for signing.
 */
export function getPrivyClient(): PrivyClient {
  // IMPORTANT: Trim whitespace from secrets - Firebase Secrets may have trailing newlines
  const appId = PRIVY_APP_ID.value().trim();
  const appSecret = PRIVY_APP_SECRET.value().trim();
  const authKey = PRIVY_AUTHORIZATION_PRIVATE_KEY.value().trim();

  if (!appId || !appSecret) {
    throw new Error("Privy credentials not configured");
  }

  if (!authKey) {
    throw new Error("Privy authorization key not configured");
  }

  // Privy SDK internally reads authorization keys from this environment variable
  // Must be set BEFORE creating the client for server-side wallet signing
  process.env.PRIVY_AUTHORIZATION_PRIVATE_KEY = authKey;

  logger.info("✅ Privy client initialized with authorization key");

  return new PrivyClient({
    appId,
    appSecret,
  });
}

/**
 * Get authorization private key formatted for Privy SDK
 *
 * Returns base64-encoded PKCS8 format without PEM headers.
 * The SDK requires this exact format for authorization_context.
 */
export function getAuthorizationPrivateKeyFormatted(): string {
  // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
  const authKey = PRIVY_AUTHORIZATION_PRIVATE_KEY.value().trim();

  if (!authKey) {
    throw new Error("Privy authorization key not configured");
  }

  // Privy SDK expects full PEM format WITH headers
  return authKey;
}

/**
 * Create a Privy policy for auto-swap restrictions
 *
 * @param name - Human-readable policy name
 * @param maxSwapAmountUsd - Maximum USD value per swap (enforced via simulation)
 * @param expirationTimestamp - Unix timestamp when policy expires
 * @param allowedTokenMints - Optional array of allowed token mints
 */
export async function createAutoSwapPolicy(params: {
  name: string;
  maxSwapAmountUsd: number;
  expirationTimestamp: number;
  allowedTokenMints?: string[];
}): Promise<string> {
  const privy = getPrivyClient();

  logger.info(`📝 Creating Privy policy: ${params.name}`);
  logger.info(`   Max swap: $${params.maxSwapAmountUsd}`);
  logger.info(`   Expires: ${new Date(params.expirationTimestamp * 1000).toISOString()}`);

  const rules: any[] = [];

  // Rule 1: Allowlist Jupiter v6 program only
  rules.push({
    name: "Only allow Jupiter v6 swaps",
    method: "signAndSendTransaction",
    conditions: [
      {
        field_source: "solana_program_instruction",
        field: "programId",
        operator: "in",
        value: [
          "JUP6LkbZbjS1jKKwapdHNy74zcZ3tLUZoi5QNyVTaV4", // Jupiter v6
        ],
      },
    ],
    action: "ALLOW",
  });

  // Rule 2: Time-based expiration
  rules.push({
    name: "Policy expires after set time",
    method: "*",
    conditions: [
      {
        field_source: "system",
        field: "current_unix_timestamp",
        operator: "lt",
        value: params.expirationTimestamp.toString(),
      },
    ],
    action: "ALLOW",
  });

  // Rule 3: Optional - token mint allowlist
  if (params.allowedTokenMints && params.allowedTokenMints.length > 0) {
    rules.push({
      name: "Only allow approved tokens",
      method: "signAndSendTransaction",
      conditions: [
        {
          field_source: "solana_token_program_instruction",
          field: "TransferChecked.mint",
          operator: "in",
          value: params.allowedTokenMints,
        },
      ],
      action: "ALLOW",
    });

    logger.info(`   Allowed tokens: ${params.allowedTokenMints.length} mints`);
  }

  // Create policy via REST API
  // Note: Node SDK doesn't yet have policy creation methods, so we use fetch
  // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
  const appId = PRIVY_APP_ID.value().trim();
  const appSecret = PRIVY_APP_SECRET.value().trim();
  const authHeader = `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`;

  const response = await fetch("https://api.privy.io/v1/policies", {
    method: "POST",
    headers: {
      "Authorization": authHeader,
      "privy-app-id": appId,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      version: "1.0",
      name: params.name,
      chain_type: "solana",
      rules,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    logger.error(`❌ Failed to create Privy policy: ${error}`);
    throw new Error(`Failed to create Privy policy: ${error}`);
  }

  const policy = await response.json();
  logger.info(`✅ Privy policy created: ${policy.id}`);

  return policy.id;
}

/**
 * Get Privy authorization key quorum ID from Firebase Functions config
 *
 * The quorum ID is returned from Privy Dashboard after registering the public key.
 * Set via: firebase functions:config:set privy.key_quorum_id="your-id-here"
 */
export function getAuthorizationKeyQuorumId(): string {
  // Firebase Functions config stores this as functions.config().privy.key_quorum_id
  // But we can't access that directly in this file, so we'll use an environment variable
  // which Firebase automatically sets from config values
  const quorumId = process.env.PRIVY_KEY_QUORUM_ID || "gnqmnu4s7zszh94i2e7f0ijk";

  logger.info(`Using Privy key quorum ID: ${quorumId}`);
  return quorumId;
}

/**
 * Get Privy prediction authorization key quorum ID
 */
export function getPredictionKeyQuorumId(): string {
  logger.info(`Using Privy prediction key quorum ID: ${PREDICTION_KEY_QUORUM_ID}`);
  return PREDICTION_KEY_QUORUM_ID;
}

/**
 * Get prediction authorization private key formatted for Privy SDK
 */
export function getPredictionAuthKeyFormatted(): string {
  const authKey = PRIVY_PREDICTION_AUTH_KEY.value().trim();

  if (!authKey) {
    throw new Error("Privy prediction authorization key not configured");
  }

  return authKey;
}

/**
 * Initialize Privy Client for prediction copy trading
 * Uses the prediction-specific authorization key
 */
export function getPrivyClientForPrediction(): PrivyClient {
  const appId = PRIVY_APP_ID.value().trim();
  const appSecret = PRIVY_APP_SECRET.value().trim();
  const authKey = PRIVY_PREDICTION_AUTH_KEY.value().trim();

  if (!appId || !appSecret) {
    throw new Error("Privy credentials not configured");
  }

  if (!authKey) {
    throw new Error("Privy prediction authorization key not configured");
  }

  // Set the prediction auth key for server-side signing
  process.env.PRIVY_AUTHORIZATION_PRIVATE_KEY = authKey;

  logger.info("✅ Privy client initialized with prediction authorization key");

  return new PrivyClient({
    appId,
    appSecret,
  });
}

/**
 * Create a Privy policy for prediction copy trading
 * Allows the Jupiter Prediction Market program
 */
export async function createPredictionCopyPolicy(params: {
  name: string;
  maxCopyAmountUsd: number;
  expirationTimestamp: number;
}): Promise<string> {
  logger.info(`📝 Creating Privy prediction policy: ${params.name}`);
  logger.info(`   Max copy amount: $${params.maxCopyAmountUsd}`);
  logger.info(`   Expires: ${new Date(params.expirationTimestamp * 1000).toISOString()}`);

  const rules: any[] = [];

  // Rule 1: Allowlist Jupiter Prediction Market program
  rules.push({
    name: "Only allow Jupiter Prediction Market",
    method: "signAndSendTransaction",
    conditions: [
      {
        field_source: "solana_program_instruction",
        field: "programId",
        operator: "in",
        value: [
          "3ZZuTbwC6aJbvteyVxXUS7gtFYdf7AuXeitx6VyvjvUp", // Jupiter Prediction Market
        ],
      },
    ],
    action: "ALLOW",
  });

  // Rule 2: Time-based expiration
  rules.push({
    name: "Policy expires after set time",
    method: "*",
    conditions: [
      {
        field_source: "system",
        field: "current_unix_timestamp",
        operator: "lt",
        value: params.expirationTimestamp.toString(),
      },
    ],
    action: "ALLOW",
  });

  // Rule 3: Allow USDC transfers (for betting)
  rules.push({
    name: "Allow USDC transfers",
    method: "signAndSendTransaction",
    conditions: [
      {
        field_source: "solana_token_program_instruction",
        field: "TransferChecked.mint",
        operator: "in",
        value: [
          "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", // USDC
        ],
      },
    ],
    action: "ALLOW",
  });

  const appId = PRIVY_APP_ID.value().trim();
  const appSecret = PRIVY_APP_SECRET.value().trim();
  const authHeader = `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`;

  const response = await fetch("https://api.privy.io/v1/policies", {
    method: "POST",
    headers: {
      "Authorization": authHeader,
      "privy-app-id": appId,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      version: "1.0",
      name: params.name,
      chain_type: "solana",
      rules,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    logger.error(`❌ Failed to create Privy prediction policy: ${error}`);
    throw new Error(`Failed to create Privy prediction policy: ${error}`);
  }

  const policy = await response.json();
  logger.info(`✅ Privy prediction policy created: ${policy.id}`);

  return policy.id;
}

/**
 * Get Solana wallet ID from Privy user DID
 *
 * The Firestore field 'privyWalletId' actually contains the Privy DID (user identifier),
 * not the wallet ID. This function looks up the user's account from Privy API and
 * extracts the actual wallet ID needed for transaction signing.
 *
 * @param privyDid - Privy DID (e.g., "privy_did:privy:cmh87nmms00rblb0dnjv8yqhj")
 * @param appId - Optional Privy app ID (if not provided, reads from secret)
 * @param appSecret - Optional Privy app secret (if not provided, reads from secret)
 * @param walletAddress - Optional wallet address to match (for users with multiple wallets)
 * @returns Wallet ID (e.g., "clabcdef1234...")
 */
export async function getWalletIdFromDid(
  privyDid: string,
  appId?: string,
  appSecret?: string,
  walletAddress?: string
): Promise<string> {
  logger.info(`🔍 Looking up wallet ID for Privy identifier: ${privyDid}`);

  // Extract user ID from DID format or use raw user ID
  // DID format: "privy_did:privy:cmh87nmms00rblb0dnjv8yqhj" → extract last part
  // Raw user ID: "j5ylfa0zk87cd8gfftz82tv7" → use as-is
  // Wallet ID: "clabcdef1234..." → this is NOT a user ID, need to handle differently

  let userId: string;
  if (privyDid.startsWith("privy_did:")) {
    // Full DID format - extract the user ID
    const parts = privyDid.split(":");
    userId = parts[parts.length - 1];
  } else if (privyDid.startsWith("cl") && privyDid.length > 20) {
    // This looks like a wallet ID (starts with "cl"), not a user ID
    // We can't look up by wallet ID, this is an error
    throw new Error(`Invalid input: received wallet ID instead of user ID/DID: ${privyDid}`);
  } else {
    // Assume it's a raw user ID
    userId = privyDid;
  }

  if (!userId) {
    throw new Error(`Invalid Privy identifier: ${privyDid}`);
  }

  logger.info(`   Privy user ID: ${userId}`);

  // Use provided credentials or read from secrets
  // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
  const privyAppId = (appId || PRIVY_APP_ID.value()).trim();
  const privyAppSecret = (appSecret || PRIVY_APP_SECRET.value()).trim();

  if (!privyAppId || !privyAppSecret) {
    throw new Error("Privy credentials not available");
  }

  const authHeader = `Basic ${Buffer.from(`${privyAppId}:${privyAppSecret}`).toString("base64")}`;

  logger.info(`   Using app ID: ${privyAppId.substring(0, 10)}...`);

  const response = await fetch(`https://api.privy.io/v1/users/${userId}`, {
    headers: {
      "Authorization": authHeader,
      "privy-app-id": privyAppId,
    },
  });

  if (!response.ok) {
    const error = await response.text();
    logger.error(`❌ Failed to fetch Privy user: ${error}`);
    throw new Error(`Failed to fetch Privy user: ${error}`);
  }

  const user = await response.json();

  // Find Solana wallet in linked accounts
  // If walletAddress is provided, match by address (for users with multiple wallets)
  const solanaWallets = user.linked_accounts?.filter(
    (account: any) => account.type === "wallet" && account.chain_type === "solana"
  ) || [];

  logger.info(`   Found ${solanaWallets.length} Solana wallet(s)`);

  if (solanaWallets.length === 0) {
    logger.error(`❌ No Solana wallet found for user ${userId}`);
    throw new Error(`No Solana wallet found for user ${userId}`);
  }

  let solanaWallet;
  if (walletAddress) {
    // Match by specific address
    solanaWallet = solanaWallets.find((w: any) => w.address === walletAddress);
    if (!solanaWallet) {
      logger.error(`❌ No wallet found with address ${walletAddress}`);
      logger.info(`   Available wallets: ${solanaWallets.map((w: any) => w.address).join(", ")}`);
      throw new Error(`No wallet found with address ${walletAddress}`);
    }
    logger.info(`✅ Found wallet by address: ${solanaWallet.id} (${walletAddress})`);
  } else {
    // Use first wallet (legacy behavior)
    solanaWallet = solanaWallets[0];
    if (solanaWallets.length > 1) {
      logger.warn(`⚠️ User has ${solanaWallets.length} wallets, using first one: ${solanaWallet.address}`);
    }
    logger.info(`✅ Found wallet ID: ${solanaWallet.id}`);
  }

  return solanaWallet.id;
}
