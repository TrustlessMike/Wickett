import * as logger from "firebase-functions/logger";
import {HELIUS_API_KEY, HELIUS_WEBHOOK_ID} from "../config/solana-config";

/**
 * Helius Webhook Manager
 *
 * Manages dynamic address addition/removal for the Helius webhook
 * Automatically adds user wallet addresses when they enable auto-convert
 * Removes addresses when they revoke delegation
 *
 * Using Helius REST API directly since the SDK has ESM/CommonJS compatibility issues
 */

const HELIUS_API_BASE = "https://api.helius.xyz/v0/webhooks";

/**
 * Interface for Helius webhook response
 */
interface HeliusWebhook {
  webhookID: string;
  wallet: string;
  webhookType: string;
  accountAddresses?: string[];
  webhookURL: string;
  transactionTypes?: string[];
}

/**
 * Add wallet address to Helius webhook
 * Called when user enables auto-convert
 */
export async function addAddressToWebhook(walletAddress: string): Promise<void> {
  try {
    logger.info(`📡 Adding address to Helius webhook: ${walletAddress}`);

    const apiKey = HELIUS_API_KEY.value();

    // Get current webhook config
    const getResponse = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`);

    if (!getResponse.ok) {
      throw new Error(`Failed to get webhook: ${getResponse.statusText}`);
    }

    const webhook: HeliusWebhook = await getResponse.json();

    // Add new address if not already present
    const currentAddresses = webhook.accountAddresses || [];

    if (currentAddresses.includes(walletAddress)) {
      logger.info(`⏭️  Address already in webhook: ${walletAddress}`);
      return;
    }

    // Update webhook with new address
    const updatedAddresses = [...currentAddresses, walletAddress];

    const updateResponse = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        webhookURL: webhook.webhookURL,
        transactionTypes: webhook.transactionTypes || ["Any"],
        accountAddresses: updatedAddresses,
        webhookType: webhook.webhookType,
      }),
    });

    if (!updateResponse.ok) {
      throw new Error(`Failed to update webhook: ${updateResponse.statusText}`);
    }

    logger.info(`✅ Address added to webhook: ${walletAddress}`);
    logger.info(`📊 Total addresses monitored: ${updatedAddresses.length}`);

  } catch (error) {
    logger.error(`❌ Failed to add address to webhook: ${error}`);
    throw new Error(`Failed to add address to Helius webhook: ${error}`);
  }
}

/**
 * Remove wallet address from Helius webhook
 * Called when user revokes auto-convert delegation
 */
export async function removeAddressFromWebhook(walletAddress: string): Promise<void> {
  try {
    logger.info(`📡 Removing address from Helius webhook: ${walletAddress}`);

    const apiKey = HELIUS_API_KEY.value();

    // Get current webhook config
    const getResponse = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`);

    if (!getResponse.ok) {
      throw new Error(`Failed to get webhook: ${getResponse.statusText}`);
    }

    const webhook: HeliusWebhook = await getResponse.json();

    // Remove address
    const currentAddresses = webhook.accountAddresses || [];
    const updatedAddresses = currentAddresses.filter(addr => addr !== walletAddress);

    if (currentAddresses.length === updatedAddresses.length) {
      logger.info(`⏭️  Address not in webhook: ${walletAddress}`);
      return;
    }

    // Update webhook
    const updateResponse = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        webhookURL: webhook.webhookURL,
        transactionTypes: webhook.transactionTypes || ["Any"],
        accountAddresses: updatedAddresses,
        webhookType: webhook.webhookType,
      }),
    });

    if (!updateResponse.ok) {
      throw new Error(`Failed to update webhook: ${updateResponse.statusText}`);
    }

    logger.info(`✅ Address removed from webhook: ${walletAddress}`);
    logger.info(`📊 Total addresses monitored: ${updatedAddresses.length}`);

  } catch (error) {
    logger.error(`❌ Failed to remove address from webhook: ${error}`);
    throw new Error(`Failed to remove address from Helius webhook: ${error}`);
  }
}

/**
 * Get all addresses currently monitored by webhook
 */
export async function getWebhookAddresses(): Promise<string[]> {
  try {
    const apiKey = HELIUS_API_KEY.value();
    const response = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`);

    if (!response.ok) {
      throw new Error(`Failed to get webhook: ${response.statusText}`);
    }

    const webhook: HeliusWebhook = await response.json();
    return webhook.accountAddresses || [];
  } catch (error) {
    logger.error(`❌ Failed to get webhook addresses: ${error}`);
    return [];
  }
}

/**
 * Get webhook statistics
 */
export async function getWebhookStats(): Promise<{
  totalAddresses: number;
  webhookId: string;
  webhookType: string;
}> {
  try {
    const apiKey = HELIUS_API_KEY.value();
    const response = await fetch(`${HELIUS_API_BASE}/${HELIUS_WEBHOOK_ID}?api-key=${apiKey}`);

    if (!response.ok) {
      throw new Error(`Failed to get webhook: ${response.statusText}`);
    }

    const webhook: HeliusWebhook = await response.json();

    return {
      totalAddresses: webhook.accountAddresses?.length || 0,
      webhookId: HELIUS_WEBHOOK_ID,
      webhookType: webhook.webhookType || "unknown",
    };
  } catch (error) {
    logger.error(`❌ Failed to get webhook stats: ${error}`);
    throw error;
  }
}
