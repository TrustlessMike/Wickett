import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { SearchUsersData, UserSearchResult } from "./types";

/**
 * Cloud Function: searchUsers
 * Search for users by username, display name, or wallet address
 * Priority: username > displayName > walletAddress
 */
export const searchUsers = onCall(
  {
    invoker: "public",
  },
  async (request) => {
  const { auth, data } = request;

  // Verify authentication
  if (!auth) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const { query, limit = 10 } = data as SearchUsersData;

  // Validate input - require minimum 2 characters
  if (!query || typeof query !== "string" || query.trim().length < 2) {
    throw new HttpsError("invalid-argument", "Search query must be at least 2 characters");
  }

  const searchQuery = query.trim().toLowerCase();

  // Remove @ if user typed it (e.g., @username)
  const cleanQuery = searchQuery.startsWith("@")
    ? searchQuery.substring(1)
    : searchQuery;

  try {
    const db = getFirestore();

    // Search users - Note: Firestore doesn't support full-text search natively
    // Priority order: username (exact/prefix) > displayName > walletAddress
    // Only include users with BOTH username AND walletAddress set
    interface ScoredResult extends UserSearchResult {
      isExactMatch: boolean;
    }
    const results: ScoredResult[] = [];
    const seenUserIds = new Set<string>();

    // Helper to add valid results (must have both username and walletAddress)
    const addIfValid = (doc: FirebaseFirestore.DocumentSnapshot, isExactMatch: boolean) => {
      if (doc.id === auth.uid) return; // Skip current user
      if (seenUserIds.has(doc.id)) return; // Skip duplicates

      const userData = doc.data();
      if (!userData) return;

      const username = userData.username;
      const walletAddress = userData.walletAddress;

      // Only include users with both username AND walletAddress
      if (!username || !walletAddress) return;

      seenUserIds.add(doc.id);
      results.push({
        userId: doc.id,
        displayName: userData.displayName || "Unknown",
        username: username,
        walletAddress: walletAddress,
        isExactMatch: isExactMatch,
      });
    };

    // Helper to capitalize first letter for case-insensitive search
    const capitalizedQuery = cleanQuery.charAt(0).toUpperCase() + cleanQuery.slice(1);

    // 1. Search by username first (highest priority)
    // Try both lowercase and original case since Firestore is case-sensitive
    const usernameSnapshot = await db
      .collection("users")
      .where("username", ">=", cleanQuery)
      .where("username", "<=", cleanQuery + "\uf8ff")
      .limit(limit * 2)
      .get();

    for (const doc of usernameSnapshot.docs) {
      const userData = doc.data();
      const isExact = userData?.username?.toLowerCase() === cleanQuery;
      addIfValid(doc, isExact);
    }

    // 2. If not enough results, search by displayName (try multiple cases)
    if (results.length < limit) {
      // Try lowercase first
      const displayNameLowerSnapshot = await db
        .collection("users")
        .where("displayName", ">=", cleanQuery)
        .where("displayName", "<=", cleanQuery + "\uf8ff")
        .limit((limit - results.length) * 2)
        .get();

      for (const doc of displayNameLowerSnapshot.docs) {
        addIfValid(doc, false);
      }

      // Try with capitalized first letter (common for names like "Mike", "John")
      if (results.length < limit && capitalizedQuery !== cleanQuery) {
        const displayNameCapSnapshot = await db
          .collection("users")
          .where("displayName", ">=", capitalizedQuery)
          .where("displayName", "<=", capitalizedQuery + "\uf8ff")
          .limit((limit - results.length) * 2)
          .get();

        for (const doc of displayNameCapSnapshot.docs) {
          addIfValid(doc, false);
        }
      }
    }

    // 3. If still not enough results, try wallet address prefix (min 4 chars)
    if (results.length < limit && cleanQuery.length >= 4) {
      const addressSnapshot = await db
        .collection("users")
        .where("walletAddress", ">=", cleanQuery)
        .where("walletAddress", "<=", cleanQuery + "\uf8ff")
        .limit((limit - results.length) * 2)
        .get();

      for (const doc of addressSnapshot.docs) {
        addIfValid(doc, false);
      }
    }

    // Sort: exact username matches first, then by displayName
    results.sort((a, b) => {
      if (a.isExactMatch && !b.isExactMatch) return -1;
      if (!a.isExactMatch && b.isExactMatch) return 1;
      return a.displayName.localeCompare(b.displayName);
    });

    // Remove internal scoring field and limit results
    const finalResults: UserSearchResult[] = results
      .slice(0, limit)
      .map(({ isExactMatch, ...rest }) => rest);

    logger.info(`🔍 User search for "${query}": ${finalResults.length} results`);

    return {
      success: true,
      data: {
        results: finalResults,
        query: cleanQuery,
      },
    };
  } catch (error: any) {
    logger.error("❌ Error searching users:", error);
    throw new HttpsError(
      "internal",
      `Failed to search users: ${error.message}`
    );
  }
});
