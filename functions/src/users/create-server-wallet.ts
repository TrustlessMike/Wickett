import * as logger from "firebase-functions/logger";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {
  PRIVY_APP_ID,
  PRIVY_APP_SECRET,
  getPredictionKeyQuorumId,
} from "../config/privy-config";

/**
 * Create a default permissive policy for server-side signing
 * This allows the auth key to sign Jupiter swap transactions
 */
async function createDefaultSigningPolicy(
  appId: string,
  appSecret: string,
  userId: string
): Promise<string> {
  const authHeader = `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`;

  // Create a permissive policy that allows Jupiter swaps
  // Policy expires in 10 years (effectively permanent for the wallet's lifetime)
  const expirationTimestamp = Math.floor(Date.now() / 1000) + (10 * 365 * 24 * 60 * 60);

  const policyResponse = await fetch("https://api.privy.io/v1/policies", {
    method: "POST",
    headers: {
      "Authorization": authHeader,
      "privy-app-id": appId,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      version: "1.0",
      name: `default-${userId.slice(-8)}-${Date.now().toString().slice(-6)}`,
      chain_type: "solana",
      rules: [
        {
          // Permissive policy - allows all transaction types
          // Jupiter swaps go through many DEX programs (Meteora, Raydium, etc.)
          // so we can't restrict by program ID
          name: "Allow all transactions",
          method: "*",
          conditions: [
            {
              field_source: "system",
              field: "current_unix_timestamp",
              operator: "lt",
              value: expirationTimestamp.toString(),
            },
          ],
          action: "ALLOW",
        },
      ],
    }),
  });

  if (!policyResponse.ok) {
    const error = await policyResponse.text();
    logger.error(`❌ Failed to create default policy: ${error}`);
    throw new Error(`Failed to create default policy: ${error}`);
  }

  const policy = await policyResponse.json();
  logger.info(`✅ Default signing policy created: ${policy.id}`);
  return policy.id;
}

/**
 * Cloud Function: Create Server-Side Wallet
 *
 * Creates a Solana wallet via Privy REST API with our authorization key
 * as an additional signer from the start. This enables auto-convert
 * functionality without needing to add the signer later (which Swift SDK
 * doesn't support).
 *
 * Flow:
 * 1. iOS logs in with Privy, gets user ID
 * 2. iOS calls this function with Privy user ID
 * 3. Server creates wallet via Privy REST API with additional_signers
 * 4. Returns wallet address to iOS
 * 5. iOS stores wallet address via updateWalletAddress
 *
 * The wallet is still user-owned (non-custodial) - the auth key just
 * enables server-side signing within policy constraints.
 */
export const createServerWallet = onCall(
  {
    secrets: [PRIVY_APP_ID, PRIVY_APP_SECRET],
    enforceAppCheck: false,
    invoker: "public",
  },
  async (request) => {
    const {privyUserId} = request.data as {
      privyUserId: string;
    };

    if (!privyUserId) {
      throw new HttpsError("invalid-argument", "privyUserId is required");
    }

    // Extract the CUID2 user ID from DID format if needed
    // DID format: "did:privy:cmii6gtti1i91jo0dvwm71see" -> "cmii6gtti1i91jo0dvwm71see"
    let userId = privyUserId;
    if (privyUserId.startsWith("did:privy:")) {
      userId = privyUserId.replace("did:privy:", "");
    }

    logger.info(`🔐 Creating server-side wallet for Privy user: ${privyUserId}`);
    logger.info(`   Extracted user ID: ${userId}`);

    // IDEMPOTENCY CHECK: Check Firestore first to prevent duplicate wallet creation
    const db = getFirestore();
    const firebaseUid = `privy_${privyUserId}`;
    const existingUserDoc = await db.collection("users").doc(firebaseUid).get();
    const existingUserData = existingUserDoc.data();

    if (existingUserData?.walletAddress && existingUserData?.privyWalletId) {
      logger.info(`📱 User already has wallet in Firestore: ${existingUserData.walletAddress}`);
      return {
        success: true,
        walletAddress: existingUserData.walletAddress,
        walletId: existingUserData.privyWalletId,
        alreadyExisted: true,
        hasAuthKey: existingUserData.walletHasAuthKey || false,
        message: "Wallet already exists (from Firestore check)",
      };
    }

    // IMPORTANT: Trim whitespace - Firebase Secrets may have trailing newlines
    const appId = PRIVY_APP_ID.value().trim();
    const appSecret = PRIVY_APP_SECRET.value().trim();
    const authKeyQuorumId = getPredictionKeyQuorumId();

    logger.info(`   App ID: ${appId.substring(0, 10)}...`);
    logger.info(`   Auth Key Quorum ID: ${authKeyQuorumId}`);

    // First, check if user already has a Solana wallet
    const authHeader = `Basic ${Buffer.from(`${appId}:${appSecret}`).toString("base64")}`;

    // Get user to check for existing wallet
    const userResponse = await fetch(`https://api.privy.io/v1/users/${userId}`, {
      headers: {
        "Authorization": authHeader,
        "privy-app-id": appId,
      },
    });

    if (!userResponse.ok) {
      const error = await userResponse.text();
      logger.error(`❌ Failed to fetch Privy user: ${error}`);
      throw new HttpsError("not-found", `Failed to fetch Privy user: ${error}`);
    }

    const userData = await userResponse.json();
    logger.info(`📋 User data: ${JSON.stringify(userData, null, 2)}`);

    // Get the user's DID for wallet ownership
    // Privy API expects "owner" object with user_id, NOT "owner_id" directly
    const ownerDid = userData.id; // This is "did:privy:cmii76t7k0eqei80csj30xypy"
    logger.info(`   User DID (wallet owner): ${ownerDid}`);

    // Check if user already has a Solana wallet
    const existingWallet = userData.linked_accounts?.find(
      (account: any) => account.type === "wallet" && account.chain_type === "solana"
    );

    if (existingWallet) {
      logger.info(`📱 User already has Solana wallet: ${existingWallet.address}`);
      logger.info(`   Wallet ID: ${existingWallet.id}`);
      logger.info(`   Wallet owner_id: ${existingWallet.owner_id}`);

      // Check if auth key is already a signer
      const hasAuthKey = existingWallet.additional_signers?.some(
        (signer: any) => signer.signer_id === authKeyQuorumId
      );
      logger.info(`   Has auth key: ${hasAuthKey}`);
      logger.info(`   Additional signers: ${JSON.stringify(existingWallet.additional_signers || [])}`);

      if (hasAuthKey) {
        // Update Firestore to mark wallet as having auth key
        // db already declared at top
        const firebaseUid = `privy_${privyUserId}`;
        await db.collection("users").doc(firebaseUid).set(
          {
            walletAddress: existingWallet.address,
            privyWalletId: existingWallet.id,
            walletHasAuthKey: true,
            updatedAt: new Date(),
          },
          {merge: true}
        );

        return {
          success: true,
          walletAddress: existingWallet.address,
          walletId: existingWallet.id,
          alreadyExisted: true,
          hasAuthKey: true,
          message: "Wallet already has authorization key",
        };
      }

      // Try to add auth key to existing wallet via REST API
      logger.info("📝 Attempting to add auth key to existing wallet...");

      try {
        const updateWalletResponse = await fetch(
          `https://api.privy.io/v1/wallets/${existingWallet.id}`,
          {
            method: "PATCH",
            headers: {
              "Authorization": authHeader,
              "privy-app-id": appId,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              additional_signers: [
                {
                  signer_id: authKeyQuorumId,
                },
              ],
            }),
          }
        );

        if (updateWalletResponse.ok) {
          const updatedWallet = await updateWalletResponse.json();
          logger.info("✅ Auth key added to existing wallet!");
          logger.info(`   Additional signers: ${JSON.stringify(updatedWallet.additional_signers)}`);

          // Update Firestore
          // db already declared at top
          const firebaseUid = `privy_${privyUserId}`;
          await db.collection("users").doc(firebaseUid).set(
            {
              walletAddress: existingWallet.address,
              privyWalletId: existingWallet.id,
              walletHasAuthKey: true,
              updatedAt: new Date(),
            },
            {merge: true}
          );

          return {
            success: true,
            walletAddress: existingWallet.address,
            walletId: existingWallet.id,
            alreadyExisted: true,
            hasAuthKey: true,
            message: "Authorization key added to existing wallet",
          };
        } else {
          const errorText = await updateWalletResponse.text();
          logger.warn(`⚠️ Could not add auth key to existing wallet: ${errorText}`);
          // Continue without auth key - wallet works but auto-convert won't
        }
      } catch (updateError: any) {
        logger.warn(`⚠️ Error adding auth key: ${updateError.message}`);
      }

      // Return existing wallet without auth key
      return {
        success: true,
        walletAddress: existingWallet.address,
        walletId: existingWallet.id,
        alreadyExisted: true,
        hasAuthKey: false,
        message: "User already has a wallet (auth key could not be added)",
      };
    }

    // Create new wallet with authorization key as additional signer
    logger.info("📝 Creating new Solana wallet with auth key and default policy...");

    // First, create a default signing policy for this wallet
    logger.info("📋 Creating default signing policy...");
    const defaultPolicyId = await createDefaultSigningPolicy(appId, appSecret, userId);
    logger.info(`✅ Default policy created: ${defaultPolicyId}`);

    const createWalletResponse = await fetch("https://api.privy.io/v1/wallets", {
      method: "POST",
      headers: {
        "Authorization": authHeader,
        "privy-app-id": appId,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        chain_type: "solana",
        // Use "owner" with user_id, NOT "owner_id" directly
        // Privy will auto-generate the owner_id from the user DID
        owner: {
          user_id: ownerDid,
        },
        additional_signers: [
          {
            signer_id: authKeyQuorumId,
            // Attach the default policy so the auth key can sign transactions
            override_policy_ids: [defaultPolicyId],
          },
        ],
      }),
    });

    if (!createWalletResponse.ok) {
      const error = await createWalletResponse.text();
      logger.error(`❌ Failed to create wallet: ${error}`);
      throw new HttpsError("internal", `Failed to create wallet: ${error}`);
    }

    const wallet = await createWalletResponse.json();

    logger.info(`✅ Wallet created successfully!`);
    logger.info(`   Address: ${wallet.address}`);
    logger.info(`   ID: ${wallet.id}`);
    logger.info(`   Additional signers: ${JSON.stringify(wallet.additional_signers)}`);

    // Update user document in Firestore with wallet address
    // db already declared at top, firebaseUid already declared at top

    await db.collection("users").doc(firebaseUid).set(
      {
        walletAddress: wallet.address,
        privyWalletId: wallet.id,
        walletCreatedServerSide: true,
        walletHasAuthKey: true,
        defaultPolicyId: defaultPolicyId,
        updatedAt: new Date(),
      },
      {merge: true}
    );

    logger.info(`✅ Updated Firestore user document: ${firebaseUid}`);

    return {
      success: true,
      walletAddress: wallet.address,
      walletId: wallet.id,
      alreadyExisted: false,
      hasAuthKey: true,
      message: "Wallet created with authorization key",
    };
  }
);
