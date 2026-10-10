/**
 * Discord Alerting System
 *
 * Sends alerts to Discord for:
 * - Copy trade failures
 * - System errors
 * - Important events (large trades, new smart money, etc.)
 */

import * as logger from "firebase-functions/logger";
import { defineSecret } from "firebase-functions/params";

export const DISCORD_WEBHOOK_URL = defineSecret("DISCORD_WEBHOOK_URL");

export type AlertLevel = "info" | "warning" | "error" | "critical";

const LEVEL_COLORS: Record<AlertLevel, number> = {
  info: 0x3498db,      // Blue
  warning: 0xf39c12,   // Orange
  error: 0xe74c3c,     // Red
  critical: 0x9b59b6,  // Purple
};

const LEVEL_EMOJI: Record<AlertLevel, string> = {
  info: "ℹ️",
  warning: "⚠️",
  error: "❌",
  critical: "🚨",
};

export interface AlertPayload {
  level: AlertLevel;
  title: string;
  message: string;
  details?: Record<string, any>;
  timestamp?: Date;
}

/**
 * Send alert to Discord
 */
export async function sendDiscordAlert(payload: AlertPayload): Promise<boolean> {
  try {
    const webhookUrl = DISCORD_WEBHOOK_URL.value();

    if (!webhookUrl) {
      logger.warn("Discord webhook not configured, skipping alert");
      return false;
    }

    const emoji = LEVEL_EMOJI[payload.level];
    const color = LEVEL_COLORS[payload.level];
    const timestamp = payload.timestamp || new Date();

    // Build embed fields from details
    const fields = payload.details
      ? Object.entries(payload.details).map(([key, value]) => ({
          name: key,
          value: String(value).substring(0, 100),
          inline: true,
        }))
      : [];

    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        embeds: [
          {
            title: `${emoji} ${payload.title}`,
            description: payload.message,
            color,
            fields,
            timestamp: timestamp.toISOString(),
            footer: { text: "Mimic Alerts" },
          },
        ],
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      logger.error("Discord API error:", error);
      return false;
    }

    return true;
  } catch (error) {
    logger.error("Failed to send Discord alert:", error);
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
  await sendDiscordAlert({
    level: "error",
    title: "Copy Trade Failed",
    message: "Failed to execute copy trade",
    details: {
      User: params.userId.substring(0, 12) + "...",
      Tracker: params.trackedWallet.substring(0, 12) + "...",
      Market: params.marketTitle || "Unknown",
      Amount: params.amount ? `$${params.amount}` : "N/A",
      Error: params.error.substring(0, 50),
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
  await sendDiscordAlert({
    level: "warning",
    title: "Copy Trade Blocked",
    message: "Copy blocked by staleness protection",
    details: {
      User: params.userId.substring(0, 12) + "...",
      Reason: params.reason,
      "Bet Age": `${params.betAge}s`,
      Market: params.marketTitle || "Unknown",
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
  await sendDiscordAlert({
    level: "info",
    title: "Copy Trade Executed",
    message: "Successfully copied trade",
    details: {
      User: params.userId.substring(0, 12) + "...",
      Tracker: params.trackedWallet.substring(0, 12) + "...",
      Direction: params.direction,
      Amount: `$${params.amount}`,
      Market: params.marketTitle || "Unknown",
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
  await sendDiscordAlert({
    level: "info",
    title: "Large Bet Detected",
    message: "Smart money placed large bet",
    details: {
      Wallet: params.wallet.substring(0, 12) + "...",
      Direction: params.direction,
      Amount: `$${params.amount}`,
      Market: params.marketTitle || params.marketAddress.substring(0, 12) + "...",
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
  await sendDiscordAlert({
    level: "critical",
    title: "System Error",
    message: `Error in ${params.function}`,
    details: {
      Function: params.function,
      Error: params.error.substring(0, 100),
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
  await sendDiscordAlert({
    level: "info",
    title: "New Smart Money Discovered",
    message: "High-performing wallet identified",
    details: {
      Wallet: params.wallet.substring(0, 12) + "...",
      "Win Rate": `${(params.winRate * 100).toFixed(1)}%`,
      "Total Bets": params.totalBets,
      PnL: `$${params.pnl.toFixed(2)}`,
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
  await sendDiscordAlert({
    level: "warning",
    title: "Rate Limit Triggered",
    message: "User hit copy trade rate limit",
    details: {
      User: params.userId.substring(0, 12) + "...",
      Copies: params.copiesInWindow,
      Window: `${params.windowMinutes} min`,
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
  const successRate =
    params.totalCopies > 0
      ? ((params.successfulCopies / params.totalCopies) * 100).toFixed(1)
      : "N/A";

  await sendDiscordAlert({
    level: "info",
    title: "Daily Summary",
    message: "Copy trading metrics for the last 24 hours",
    details: {
      "Total Copies": params.totalCopies,
      Successful: params.successfulCopies,
      Failed: params.failedCopies,
      Blocked: params.blockedCopies,
      "Success Rate": `${successRate}%`,
      Volume: `$${params.totalVolume.toFixed(2)}`,
      "Active Users": params.activeUsers,
    },
  });
}
