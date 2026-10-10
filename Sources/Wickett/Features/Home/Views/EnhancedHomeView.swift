import SwiftUI

// MARK: - Balance Chart Components

struct BalanceChart: View {
    let dataPoints: [Double]
    let lineColor: Color
    let showGradient: Bool

    init(data: [Double], color: Color = BrandColors.primary, showGradient: Bool = true) {
        self.dataPoints = data
        self.lineColor = color
        self.showGradient = showGradient
    }

    var body: some View {
        GeometryReader { geometry in
            if dataPoints.count > 1 {
                ZStack {
                    // Gradient Fill
                    if showGradient {
                        LineGraphFill(dataPoints: dataPoints)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [lineColor.opacity(0.3), lineColor.opacity(0.0)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                    // Line Stroke
                    LineGraph(dataPoints: dataPoints)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            } else {
                // Placeholder line for empty state
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [5]))
            }
        }
    }
}

struct LineGraph: Shape {
    var dataPoints: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard dataPoints.count > 1 else { return path }

        let stepX = rect.width / CGFloat(dataPoints.count - 1)
        let minPoint = dataPoints.min() ?? 0
        let maxPoint = dataPoints.max() ?? 1
        let range = maxPoint - minPoint

        // If all values are the same (flat line), draw in the middle
        if range == 0 {
            let yPosition = rect.height * 0.5 // Center the flat line
            path.move(to: CGPoint(x: 0, y: yPosition))
            path.addLine(to: CGPoint(x: rect.width, y: yPosition))
            return path
        }

        let yRatio = rect.height / range

        // Start point
        let p1 = CGPoint(x: 0, y: rect.height - (dataPoints[0] - minPoint) * yRatio)
        path.move(to: p1)

        for index in 1..<dataPoints.count {
            let p2 = CGPoint(
                x: stepX * CGFloat(index),
                y: rect.height - (dataPoints[index] - minPoint) * yRatio
            )
            path.addLine(to: p2)
        }

        return path
    }
}

struct LineGraphFill: Shape {
    var dataPoints: [Double]

    func path(in rect: CGRect) -> Path {
        let graph = LineGraph(dataPoints: dataPoints)
        var path = graph.path(in: rect)

        // Close the path for the gradient
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()

        return path
    }
}

// MARK: - Enhanced Home View

struct EnhancedHomeView: View {
    let user: User
    let onSettings: () -> Void
    let onSignOut: () async -> Void
    let onPayTap: () -> Void
    let onRequestTap: () -> Void

    @EnvironmentObject var walletService: SolanaWalletService
    @StateObject private var historyManager = PortfolioHistoryManager.shared
    @State private var recentTransactions: [Transaction] = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Account Balance Card
                    AccountBalanceCard(
                        totalUSD: walletService.totalUSDValue,
                        change24h: walletService.total24hChange,
                        lastUpdated: walletService.lastUpdated,
                        isLoading: walletService.isLoading,
                        chartData: historyManager.chartData,
                        hasBalances: !walletService.balances.isEmpty
                    )
                    .padding(.horizontal)
                    .padding(.top, 10)

                    // Quick Actions Row
                    HomeQuickActionsRow(
                        onPayTap: onPayTap,
                        onRequestTap: onRequestTap
                    )
                    .padding(.horizontal)

                    // Recent Transactions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recent Activity")
                                .font(.headline)
                            Spacer()
                            // Only show "View All" if there are transactions
                            if !recentTransactions.isEmpty {
                                Button("View All") {
                                    // TODO: Navigate to full transaction history
                                }
                                .font(.subheadline)
                                .foregroundColor(BrandColors.primary)
                            }
                        }
                        .padding(.horizontal)

                        if recentTransactions.isEmpty {
                            EmptyTransactionsView(onPayTap: onPayTap)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(recentTransactions) { transaction in
                                    TransactionRow(transaction: transaction)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 100)
                }
            }
            .navigationTitle("Welcome, \(user.displayName)")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

// MARK: - Account Balance Card

struct AccountBalanceCard: View {
    let totalUSD: Decimal
    let change24h: Decimal?
    let lastUpdated: Date?
    let isLoading: Bool
    let chartData: [Double]
    let hasBalances: Bool

    private var formattedBalance: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: totalUSD)) ?? "$0.00"
    }

    private var formattedChange: String? {
        guard let change = change24h else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        let decimal = change / 100
        return formatter.string(from: NSDecimalNumber(decimal: decimal))
    }

    private var changeColor: Color {
        guard let change = change24h else { return .secondary }
        return change >= 0 ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Section: Balance
            VStack(alignment: .leading, spacing: 8) {
                Text("Total Balance")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                if isLoading && !hasBalances {
                    // Show skeleton loading instead of $0.00
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 200, height: 44)
                        .shimmer()
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formattedBalance)
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                if let formattedChange = formattedChange {
                    HStack(spacing: 4) {
                        Image(systemName: (change24h ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption)
                            .fontWeight(.semibold)

                        Text(formattedChange)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Today")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .foregroundColor(changeColor)
                }
            }
            .padding(20)

            // Chart Section (Robinhood/Coinbase style)
            // Only show chart if we have meaningful data AND a real balance
            // Hide completely when balance is too low - cleaner UX
            if chartData.count >= 10 && totalUSD > 1 {
                BalanceChart(data: chartData, color: .white.opacity(0.9), showGradient: true)
                    .frame(height: 100)
                    .padding(.bottom, 0) // Extend to bottom
            }
            // No else - just hide the chart entirely when not meaningful
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.primaryGradient)
        .cornerRadius(20)
        .shadow(color: BrandColors.primary.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Transaction Row & Empty View

struct TransactionRow: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: transaction.type.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.description)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text(transaction.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(transaction.formattedAmount)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(amountColor)
        }
        .padding(.vertical, 12)
    }

    private var iconColor: Color {
        switch transaction.type {
        case .payment: return .red
        case .deposit: return .green
        case .withdrawal: return .orange
        case .conversion: return .blue
        }
    }

    private var amountColor: Color {
        transaction.type == .deposit ? .green : .primary
    }
}

struct EmptyTransactionsView: View {
    let onPayTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 44))
                .foregroundColor(BrandColors.primary.opacity(0.6))

            Text("Send your first payment")
                .font(.headline)
                .foregroundColor(.primary)

            Button(action: onPayTap) {
                Text("Pay Someone")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(BrandColors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}

// MARK: - Home Quick Actions

struct HomeQuickActionsRow: View {
    let onPayTap: () -> Void
    let onRequestTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            QuickActionPill(
                icon: "arrow.up.circle.fill",
                title: "Pay",
                color: BrandColors.primary,
                action: onPayTap
            )
            QuickActionPill(
                icon: "arrow.down.circle.fill",
                title: "Request",
                color: .green,
                action: onRequestTap
            )
        }
    }
}

struct QuickActionPill: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
        .foregroundColor(.primary)
    }
}

#Preview {
    EnhancedHomeView(
        user: User(
            id: "test",
            email: "test@example.com",
            name: "Test User",
            walletAddress: "ABC123XYZ789ABC123XYZ789", username: nil
        ),
        onSettings: {},
        onSignOut: {},
        onPayTap: {},
        onRequestTap: {}
    )
}
