import SwiftUI

struct WalletView: View {
    let user: User

    @EnvironmentObject var walletService: SolanaWalletService
    @StateObject private var delegationManager = DelegationManager.shared
    @StateObject private var remoteConfig = RemoteConfigManager.shared
    @State private var showError = false
    @State private var showAutoConvertSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Total Balance Card
                    if walletService.isLoading && walletService.balances.isEmpty {
                        SkeletonBalanceCard()
                            .padding(.horizontal)
                    } else {
                        TotalBalanceCard(
                            totalUSD: walletService.totalUSDValue,
                            change24h: walletService.total24hChange,
                            lastUpdated: walletService.lastUpdated
                        )
                        .padding(.horizontal)
                    }

                    // Quick Actions
                    QuickActionsRow(user: user)
                        .padding(.horizontal)

                    // Auto-Convert Card (New Entry Point)
                    Button(action: {
                        showAutoConvertSettings = true
                    }) {
                        AutoConvertCard(hasActiveDelegation: delegationManager.delegationStatus?.hasActiveDelegation ?? false)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .padding(.horizontal)

                    // Token Holdings
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Holdings")
                            .font(.headline)
                            .padding(.horizontal)

                        if walletService.isLoading && walletService.balances.isEmpty {
                            SkeletonTokenList(count: 5)
                                .padding(.horizontal)
                        } else if walletService.balances.filter({ $0.hasBalance }).isEmpty {
                            EmptyBalancesView()
                                .padding(.horizontal)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(walletService.balances.filter { $0.hasBalance }) { balance in
                                    TokenBalanceRow(balance: balance)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                guard let walletAddress = user.walletAddress else { return }
                await walletService.refreshBalances(walletAddress: walletAddress, force: true)
                await delegationManager.fetchDelegationStatus()
            }
            .sheet(isPresented: $showAutoConvertSettings) {
                NavigationStack {
                    AutoConvertSettingsView()
                        // We need to pass environment objects if they aren't inherited automatically (sheets sometimes break this)
                        .environmentObject(HybridPrivyService.shared)
                }
            }
            .alert("Error", isPresented: $showError, presenting: walletService.error) { error in
                Button("OK") {
                    showError = false
                }
            } message: { error in
                Text(error.localizedDescription)
            }
            .onChange(of: walletService.error) { newError in
                showError = newError != nil
            }
            .onAppear {
                // Refresh delegation status to keep card updated
                Task {
                    await delegationManager.fetchDelegationStatus()
                }
            }
        }
    }

}

// MARK: - AutoConvert Card

struct AutoConvertCard: View {
    let hasActiveDelegation: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(hasActiveDelegation ? Color.green.opacity(0.1) : BrandColors.primary.opacity(0.1))
                    .frame(width: 48, height: 48)

                Image(systemName: hasActiveDelegation ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .font(.title3)
                    .foregroundColor(hasActiveDelegation ? .green : BrandColors.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Convert")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(hasActiveDelegation ? "Active • Portfolio Balancing On" : "Automate your savings instantly")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(hasActiveDelegation ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Total Balance Card

struct TotalBalanceCard: View {
    let totalUSD: Decimal
    let change24h: Decimal?
    let lastUpdated: Date?

    private var formattedTotal: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalUSD as NSDecimalNumber) ?? "$0.00"
    }

    private var formattedChange: String? {
        guard let change = change24h else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: (change / 100) as NSDecimalNumber)
    }

    private var changeColor: Color {
        guard let change = change24h else { return .secondary }
        return change >= 0 ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Total Balance")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                Spacer()

                if let lastUpdated = lastUpdated {
                    Text("Updated \(timeAgo(lastUpdated))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Text(formattedTotal)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            if let formattedChange = formattedChange {
                HStack(spacing: 6) {
                    Image(systemName: (change24h ?? 0) >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption)
                        .fontWeight(.semibold)

                    Text(formattedChange)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Today")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .foregroundColor(changeColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandColors.primaryGradient)
        .cornerRadius(20)
        .shadow(color: BrandColors.primary.opacity(0.4), radius: 15, x: 0, y: 8)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        else if seconds < 3600 { return "\(seconds / 60)m ago" }
        else { return "\(seconds / 3600)h ago" }
    }
}

// MARK: - Quick Actions Row
// (Same as before)
struct QuickActionsRow: View {
    let user: User
    @State private var showSendSheet = false
    @State private var showRequestSheet = false
    @State private var showConvertSheet = false
    @State private var showBuySheet = false
    @State private var showSellSheet = false
    @StateObject private var remoteConfig = RemoteConfigManager.shared

    var body: some View {
        HStack(spacing: 12) {
            QuickActionButton(icon: "arrow.up.circle.fill", title: "Pay", color: .blue) { showSendSheet = true }
            QuickActionButton(icon: "arrow.down.circle.fill", title: "Get Paid", color: .green) { showRequestSheet = true }

            if remoteConfig.enableOnramp {
                QuickActionButton(icon: "plus.circle.fill", title: "Top Up", color: .orange) { showBuySheet = true }
            }

            if remoteConfig.enableOfframp {
                QuickActionButton(icon: "minus.circle.fill", title: "Cash Out", color: .red) { showSellSheet = true }
            }

            QuickActionButton(icon: "arrow.triangle.swap", title: "Convert", color: .purple) { showConvertSheet = true }
        }
        .sheet(isPresented: $showSendSheet) { SendView(user: user) }
        .sheet(isPresented: $showRequestSheet) { CreateRequestView(user: user) }
        .sheet(isPresented: $showConvertSheet) { SwapView() }
        .sheet(isPresented: $showBuySheet) { CoinbaseOnrampView() }
        .sheet(isPresented: $showSellSheet) { CoinbaseOfframpView() }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
}

// MARK: - Token Balance Row

struct TokenBalanceRow: View {
    let balance: TokenBalance

    var body: some View {
        HStack(spacing: 12) {
            TokenImageView(token: balance.token, size: 44)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(balance.token.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(balance.displayUSD)
                    .font(.body)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                if let change = balance.change24h {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2)
                        Text(formatPercentage(change))
                            .font(.caption)
                    }
                    .foregroundColor(change >= 0 ? .green : .red)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Removed background for cleaner list look (matches Home view)
        // .background(Color(UIColor.secondarySystemBackground))
        // .cornerRadius(12)
    }

    private func formatPercentage(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.positivePrefix = "+"
        return formatter.string(from: (value / 100) as NSDecimalNumber) ?? "0%"
    }
}

// MARK: - Empty Balances View
struct EmptyBalancesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bitcoinsign.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No tokens yet")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}


#Preview {
    WalletView(
        user: User(
            id: "test",
            email: "test@example.com",
            name: "Test User",
            walletAddress: "ABC123XYZ789", username: nil
        )
    )
}
