import Foundation

/// Represents a recent payment recipient
struct RecentRecipient: Identifiable, Codable {
    let id: String
    let address: String
    let displayName: String?
    let lastSentAt: Date
    let frequency: Int
    let tokenType: String?

    var initials: String {
        guard let name = displayName else { return "?" }
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            let first = components[0].prefix(1)
            let last = components[1].prefix(1)
            return "\(first)\(last)".uppercased()
        } else if let first = components.first?.prefix(1) {
            return String(first).uppercased()
        }
        return "?"
    }

    var formattedAddress: String {
        guard address.count > 8 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

/// Service for managing recent recipients
@MainActor
class RecentRecipientsService: ObservableObject {
    static let shared = RecentRecipientsService()

    @Published var recentRecipients: [RecentRecipient] = []
    @Published var isLoading = false

    private let firebaseClient = FirebaseCallableClient.shared

    private init() {}

    /// Fetch recent recipients from Firebase
    func fetchRecentRecipients(userId: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await firebaseClient.call(
                "getRecentRecipients",
                data: ["limit": 10]
            )

            guard let response = result.data as? [String: Any] else {
                recentRecipients = []
                return
            }

            guard let recipientsData = response["recipients"] as? [[String: Any]] else {
                recentRecipients = []
                return
            }

            recentRecipients = recipientsData.compactMap { dict -> RecentRecipient? in
                guard let id = dict["id"] as? String,
                      let address = dict["address"] as? String,
                      let lastSentAtString = dict["lastSentAt"] as? String,
                      let frequency = dict["frequency"] as? Int else {
                    return nil
                }

                let displayName = dict["displayName"] as? String
                let tokenType = dict["tokenType"] as? String

                // Parse ISO date string
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                guard let lastSentAt = dateFormatter.date(from: lastSentAtString) else {
                    // Fallback: try without fractional seconds
                    dateFormatter.formatOptions = [.withInternetDateTime]
                    if let fallbackDate = dateFormatter.date(from: lastSentAtString) {
                        return RecentRecipient(
                            id: id,
                            address: address,
                            displayName: displayName,
                            lastSentAt: fallbackDate,
                            frequency: frequency,
                            tokenType: tokenType
                        )
                    }
                    return nil
                }

                return RecentRecipient(
                    id: id,
                    address: address,
                    displayName: displayName,
                    lastSentAt: lastSentAt,
                    frequency: frequency,
                    tokenType: tokenType
                )
            }

        } catch {
            recentRecipients = []
        }
    }

    /// Search for a user by display name, email, or username
    func searchUser(query: String) async -> [RecentRecipient] {
        guard !query.isEmpty else { return [] }

        // TODO: Implement user search via Firebase function
        // For now, return empty array

        return []
    }
}
