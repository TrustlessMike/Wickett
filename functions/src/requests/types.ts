import { Timestamp } from "firebase-admin/firestore";

export type RequestStatus = "pending" | "paid" | "expired" | "rejected";

export interface PortfolioAllocation {
  id: string;
  token: string;
  percentage: number;
}

export interface PaymentTransaction {
  id: string;
  token: string;
  amount: number;
  fiatValue: number;
  txSignature: string;
}

export interface PaymentRequest {
  requesterId: string;
  requesterName: string;
  requesterAddress: string;
  recipientId?: string;
  recipientName?: string;
  amount: number;
  tokenSymbol: string;
  tokenMint?: string; // For SPL tokens
  isFixedAmount: boolean;
  memo: string;
  createdAt: Timestamp;
  expiresAt: Timestamp;
  status: RequestStatus;
  paymentCount: number;
  lastPaidAt?: Timestamp;

  // NEW: Fiat-based request fields
  currency?: string; // "USD", "EUR", etc.
  requesterPortfolio?: PortfolioAllocation[]; // Receiver's preferred portfolio

  // NEW: Payment details (filled when paid)
  paidBy?: string;
  paidAt?: Timestamp;
  paymentToken?: string;
  transactions?: PaymentTransaction[];
}

export interface ReceivedRequest {
  requestId: string;
  viewedAt?: Timestamp;
  status: RequestStatus;
  rejectionMessage?: string;
}

export interface CreateRequestData {
  amount: number;
  tokenSymbol: string;
  isFixedAmount: boolean;
  memo: string;
}

export interface CreateFiatRequestData {
  amount: number;
  currency: string;
  portfolio: PortfolioAllocation[];
  isFixedAmount: boolean;
  memo: string;
}

export interface SendRequestData {
  requestId: string;
  recipientUserId: string;
}

export interface FulfillRequestData {
  requestId: string;
  amount?: number; // Optional for flexible amounts
  signedTransaction: string;
}

export interface RejectRequestData {
  requestId: string;
  message?: string;
}

export interface SearchUsersData {
  query: string;
  limit?: number;
}

export interface UserSearchResult {
  userId: string;
  displayName: string;
  username: string | null;
  walletAddress: string;
}
