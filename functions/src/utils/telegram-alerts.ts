/**
 * Telegram Alerting System
 *
 * Sends alerts to Telegram for:
 * - Copy trade failures
 * - System errors
 * - Important events (large trades, new smart money, etc.)
 *
 * Setup:
 * 1. Create bot via @BotFather on Telegram
 * 2. Get your chat ID via @userinfobot
 * 3. Set secrets: firebase functions:secrets:set TELEGRAM_BOT_TOKEN
 *                 firebase functions:secrets:set TELEGRAM_CHAT_ID
 */

import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";

export const TELEGRAM_BOT_TOKEN = defineSecret("TELEGRAM_BOT_TOKEN");
export const TELEGRAM_CHAT_ID = defineSecret("TELEGRAM_CHAT_ID");

export type AlertLevel = "info" | "warning" | "error" | "critical";

export interface AlertPayload {
  level: AlertLevel;
  title: string;
  message: string;
  details?: Record<string, any>;
  timestamp?: Date;
}

const LEVEL_EMOJI: Record<AlertLevel, string> = {
  info: "ℹ️",
  warning: "⚠️",
  error: "❌",
  critical: "🚨",
};

/**
 * Send alert to Telegram
 */
export async function sendTelegramAlert(payload: AlertPayload): Promise<boolean> {
  try {
    const botToken = TELEGRAM_BOT_TOKEN.value();
    const chatId = TELEGRAM_CHAT_ID.value();

    if (!botToken || !chatId) {
      logger.warn("Telegram credentials not configured, skipping alert");
      return false;
    }

    const emoji = LEVEL_EMOJI[payload.level];
    const timestamp = payload.timestamp || new Date();

    // Format message
    let text = `${emoji} *${payload.title}*\n\n`;
    text += `${payload.message}\n\n`;

    if (payload.details) {
      text += "```\n";
      for (const [key, value] of Object.entries(payload.details)) {
        const displayValue = typeof value === "object" ? JSON.stringify(value) : String(value);
        text += `${key}: ${displayValue.substring(0, 100)}\n`;
      }
      text += "```\n";
    }

    text += `\n_${timestamp.toISOString()}_`;

    const response = await fetch(
      `https://api.telegram.org/bot${botToken}/sendMessage`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          chat_id: chatId,
          text,
          parse_mode: "Markdown",
          disable_web_page_preview: true,
        }),
      }
    );

    if (!response.ok) {
      const error = await response.text();
      logger.error("Telegram API error:", error);
      return false;
    }

    return true;
  } catch (error) {
    logger.error("Failed to send Telegram alert:", error);
    return false;
  }
}

// ============================================
// Pre-built alert functions for common events
// ============================================

/**
 * Alert: Copy trade failed
 */
export async function alertCopyFailed(params: {
  userId: string;
  trackedWallet: string;
  marketTitle?: string;
  error: string;
  amount?: number;
}): Promise<void> {
  await sendTelegramAlert({
    level: "error",
    title: "Copy Trade Failed",
    message: `Failed to execute copy trade for user`,
    details: {
      user: params.userId.substring(0, 12) + "...",
      tracker: params.trackedWallet.substring(0, 12) + "...",
      market: params.marketTitle || "Unknown",
      amount: params.amount ? `$${params.amount}` : "N/A",
      error: params.error,
    },
  });
}

/**
 * Alert: Copy trade blocked by staleness
 */
export async function alertCopyBlocked(params: {
  userId: string;
  reason: string;
  betAge: number;
  marketTitle?: string;
}): Promise<void> {
  await sendTelegramAlert({
    level: "warning",
    title: "Copy Trade Blocked",
    message: `Copy blocked by staleness protection`,
    details: {
      user: params.userId.substring(0, 12) + "...",
      reason: params.reason,
      betAge: `${params.betAge}s`,
      market: params.marketTitle || "Unknown",
    },
  });
}

/**
 * Alert: Copy trade executed successfully
 */
export async function alertCopySuccess(params: {
  userId: string;
  trackedWallet: string;
  direction: string;
  amount: number;
  signature: string;
  marketTitle?: string;
}): Promise<void> {
  await sendTelegramAlert({
    level: "info",
    title: "Copy Trade Executed",
    message: `Successfully copied trade`,
    details: {
      user: params.userId.substring(0, 12) + "...",
      tracker: params.trackedWallet.substring(0, 12) + "...",
      direction: params.direction,
      amount: `$${params.amount}`,
      market: params.marketTitle || "Unknown",
      tx: params.signature.substring(0, 20) + "...",
    },
  });
}

/**
 * Alert: Large smart money bet detected
 */
export async function alertLargeBet(params: {
  wallet: string;
  direction: string;
  amount: number;
  marketTitle?: string;
  marketAddress: string;
}): Promise<void> {
  await sendTelegramAlert({
    level: "info",
    title: "Large Bet Detected",
    message: `Smart money placed large bet`,
    details: {
      wallet: params.wallet.substring(0, 12) + "...",
      direction: params.direction,
      amount: `$${params.amount}`,
      market: params.marketTitle || params.marketAddress.substring(0, 12) + "...",
    },
  });
}

/**
 * Alert: System error
 */
export async function alertSystemError(params: {
  function: string;
  error: string;
  context?: Record<string, any>;
}): Promise<void> {
  await sendTelegramAlert({
    level: "critical",
    title: "System Error",
    message: `Error in ${params.function}`,
    details: {
      function: params.function,
      error: params.error,
      ...params.context,
    },
  });
}

/**
 * Alert: New smart money wallet discovered
 */
export async function alertNewSmartMoney(params: {
  wallet: string;
  winRate: number;
  totalBets: number;
  pnl: number;
}): Promise<void> {
  await sendTelegramAlert({
    level: "info",
    title: "New Smart Money Discovered",
    message: `High-performing wallet identified`,
    details: {
      wallet: params.wallet.substring(0, 12) + "...",
      winRate: `${(params.winRate * 100).toFixed(1)}%`,
      totalBets: params.totalBets,
      pnl: `$${params.pnl.toFixed(2)}`,
    },
  });
}

/**
 * Alert: Webhook issue
 */
export async function alertWebhookIssue(params: {
  webhookId: string;
  error: string;
}): Promise<void> {
  await sendTelegramAlert({
    level: "critical",
    title: "Webhook Issue",
    message: `Helius webhook encountered an error`,
    details: {
      webhookId: params.webhookId,
      error: params.error,
    },
  });
}

/**
 * Alert: Rate limit triggered
 */
export async function alertRateLimited(params: {
  userId: string;
  copiesInWindow: number;
  windowMinutes: number;
}): Promise<void> {
  await sendTelegramAlert({
    level: "warning",
    title: "Rate Limit Triggered",
    message: `User hit copy trade rate limit`,
    details: {
      user: params.userId.substring(0, 12) + "...",
      copies: params.copiesInWindow,
      window: `${params.windowMinutes} min`,
    },
  });
}

/**
 * Daily summary alert
 */
export async function alertDailySummary(params: {
  totalCopies: number;
  successfulCopies: number;
  failedCopies: number;
  blockedCopies: number;
  totalVolume: number;
  activeUsers: number;
  newWallets: number;
}): Promise<void> {
  const successRate = params.totalCopies > 0
    ? ((params.successfulCopies / params.totalCopies) * 100).toFixed(1)
    : "N/A";

  await sendTelegramAlert({
    level: "info",
    title: "Daily Summary",
    message: `Copy trading metrics for the last 24 hours`,
    details: {
      "Total Copies": params.totalCopies,
      "Successful": params.successfulCopies,
      "Failed": params.failedCopies,
      "Blocked (stale)": params.blockedCopies,
      "Success Rate": `${successRate}%`,
      "Total Volume": `$${params.totalVolume.toFixed(2)}`,
      "Active Users": params.activeUsers,
      "New Wallets": params.newWallets,
    },
  });
}
