import SwiftUI

struct ActivityView: View {
    let user: User

    @StateObject private var activityService = ActivityService.shared
    @State private var searchText = ""
    @State private var selectedFilter: TransactionFilter = .all

    var filteredActivities: [ActivityItem] {
        var result = activityService.filteredActivities(filter: selectedFilter)

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter { activity in
                activity.title.localizedCaseInsensitiveContains(searchText) ||
                activity.subtitle.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter Chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(TransactionFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.displayName,
                                isSelected: selectedFilter == filter,
                                action: {
                                    selectedFilter = filter
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor.systemBackground))

                Divider()

                // Activity List
                if activityService.isLoading && activityService.activities.isEmpty {
                    ScrollView {
                        SkeletonTransactionList(count: 8)
                            .padding()
                    }
                } else if filteredActivities.isEmpty {
                    EmptyActivityView(searchText: searchText, filter: selectedFilter)
                } else {
                    List {
                        ForEach(groupedActivities.keys.sorted(by: >), id: \.self) { date in
                            Section {
                                ForEach(groupedActivities[date] ?? []) { activity in
                                    ActivityRow(activity: activity)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                }
                            } header: {
                                Text(formatSectionDate(date))
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Load More Button
                        if activityService.hasMore {
                            Section {
                                Button(action: {
                                    Task {
                                        await activityService.loadMore()
                                    }
                                }) {
                                    HStack {
                                        Spacer()
                                        if activityService.isLoadingMore {
                                            ProgressView()
                                                .padding(.trailing, 8)
                                            Text("Loading...")
                                        } else {
                                            Text("View More")
                                        }
                                        Spacer()
                                    }
                                    .foregroundColor(BrandColors.primary)
                                    .padding(.vertical, 12)
                                }
                                .disabled(activityService.isLoadingMore)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            }
                        }

                        // Spacer for custom tab bar
                        Color.clear
                            .frame(height: 80)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search activity")
                    .refreshable {
                        await activityService.refresh()
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await activityService.fetchActivity()
            }
        }
    }

    // MARK: - Helpers

    private var groupedActivities: [String: [ActivityItem]] {
        Dictionary(grouping: filteredActivities) { activity in
            Calendar.current.startOfDay(for: activity.timestamp).ISO8601Format()
        }
    }

    private func formatSectionDate(_ dateString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Activity Row

struct ActivityRow: View {
    let activity: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: activity.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(activity.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Amount and Status
            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedAmount)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(amountColor)

                Text(formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch activity.status {
        case .completed:
            return .green
        case .pending:
            return .orange
        case .failed:
            return .red
        }
    }

    private var amountColor: Color {
        switch activity.type {
        case .paymentReceived, .autoConvert:
            return .green
        case .paymentSent, .requestSent:
            return .primary
        case .requestReceived:
            return activity.status == .pending ? .orange : .primary
        }
    }

    private var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2

        let prefix: String
        switch activity.type {
        case .paymentReceived:
            prefix = "+"
        case .paymentSent:
            prefix = "-"
        default:
            prefix = ""
        }

        let amountString = formatter.string(from: NSNumber(value: activity.amount)) ?? "$0.00"
        return "\(prefix)\(amountString)"
    }

    private var formattedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: activity.timestamp, relativeTo: Date())
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? BrandColors.primary : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(20)
        }
    }
}

// MARK: - Empty Activity View

struct EmptyActivityView: View {
    let searchText: String
    let filter: TransactionFilter

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 50))
                .foregroundColor(.secondary)

            Text(emptyMessage)
                .font(.headline)
                .foregroundColor(.secondary)

            Text(emptySubMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }

    private var emptyMessage: String {
        if !searchText.isEmpty {
            return "No results found"
        } else if filter != .all {
            return "No \(filter.displayName.lowercased())"
        } else {
            return "No transactions yet"
        }
    }

    private var emptySubMessage: String {
        if !searchText.isEmpty {
            return "Try adjusting your search or filter"
        } else {
            return "Your activity will appear here"
        }
    }
}

// MARK: - Transaction Filter

enum TransactionFilter: CaseIterable {
    case all
    case deposits
    case payments
    case withdrawals
    case conversions

    var displayName: String {
        switch self {
        case .all: return "All"
        case .deposits: return "Deposits"
        case .payments: return "Payments"
        case .withdrawals: return "Withdrawals"
        case .conversions: return "Conversions"
        }
    }
}

#Preview {
    ActivityView(
        user: User(
            id: "test",
            email: "test@example.com",
            name: "Test User",
            walletAddress: "ABC123XYZ789", username: nil
        )
    )
}
