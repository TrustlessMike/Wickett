import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.syndicatemike.Wickett", category: "AutoConvertSettings")

struct AutoConvertSettingsView: View {
    @StateObject private var delegationManager = DelegationManager.shared
    @EnvironmentObject var privyService: HybridPrivyService
    @Environment(\.colorScheme) var colorScheme

    @State private var showPortfolioEditor = false
    @State private var portfolio: [PortfolioAllocation] = []
    @State private var perSwapLimit: Double = 500
    @State private var dailyLimit: Double = 2000
    private let durationDays: Int = 90 // Fixed 90-day expiration for security

    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background - adapts to dark mode
            Group {
                if colorScheme == .dark {
                    Color(UIColor.systemBackground)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.9, green: 0.96, blue: 1.0), Color.white],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .ignoresSafeArea()

            // Floating Coins/Gems Background (Simplified) - only in light mode
            if colorScheme == .light {
                GeometryReader { geo in
                    Circle()
                        .fill(Color.yellow.opacity(0.1))
                        .frame(width: 100, height: 100)
                        .position(x: 50, y: 100)
                    Circle()
                        .fill(Color.blue.opacity(0.05))
                        .frame(width: 150, height: 150)
                        .position(x: geo.size.width - 40, y: 300)
                    Image(systemName: "suit.diamond.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color.blue.opacity(0.1))
                        .position(x: geo.size.width - 80, y: 80)
                }
                .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: 20) {
                    // Level Header
                    levelHeader

                    // Quest Status Card
                    questStatusCard

                    if !hasActiveDelegation {
                        // Portfolio Setup Quest
                        portfolioQuestSection

                        // Safety Limits Quest
                        safetyLimitsQuestSection
                    }

                    // Main Action Button
                    mainActionButton

                    Spacer(minLength: 100)
                }
                .padding(20)
            }
            .navigationTitle("Auto-Convert")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPortfolioEditor) {
                PortfolioAllocationView(
                    portfolio: $portfolio,
                    onSave: { newPortfolio in
                        portfolio = newPortfolio
                        showPortfolioEditor = false
                    }
                )
            }
            .alert("Auto-Convert", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .task {
                await loadDelegationStatus()
            }

            if showConfetti {
                ConfettiView()
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showConfetti = false
                        }
                    }
            }
        }
    }

    // MARK: - Level Header

    private var levelHeader: some View {
        VStack(spacing: 8) {
            Text("Financial Explorer")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.top, 8)

            // Level Progress
            GameProgressBar(progress: 0.3)
                .frame(maxWidth: 200)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Quest Status Card (Hero)

    private var questStatusCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(hasActiveDelegation ? "Auto-Pilot Active" : "Setup Required")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(hasActiveDelegation ? "Converting payments automatically" : "Configure to start automating")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Steps Progress
                if !hasActiveDelegation {
                    VStack(alignment: .leading, spacing: 4) {
                        GameProgressBar(progress: stepsProgress, height: 8)

                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.blue)
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.gray.opacity(0.3))
                            Image(systemName: "dollarsign.circle.fill")
                                .foregroundColor(.gray.opacity(0.3))

                            Spacer()

                            Text("\(completedSteps)/3 Steps Complete")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Reward Chest / Status Icon
            ZStack {
                Circle()
                    .fill(colorScheme == .dark ? Color(UIColor.tertiarySystemBackground) : Color(red: 0.95, green: 0.95, blue: 1.0))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle().stroke(BrandColors.primary, lineWidth: 2)
                    )

                Image(systemName: hasActiveDelegation ? "checkmark.seal.fill" : "briefcase.fill")
                    .font(.system(size: 30))
                    .foregroundColor(BrandColors.primary)
            }
        }
        .gameCardStyle()
    }

    // MARK: - Portfolio Quest

    private var portfolioQuestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("YOUR PORTFOLIO")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(.secondary)
                Text("ALLOCATION")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary.opacity(0.6))
            }

            Button(action: { showPortfolioEditor = true }) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(portfolio.isEmpty ? "Setup Portfolio" : "Portfolio Ready")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Spacer()

                        // Diamond Progress Bar placeholder
                        GameProgressBar(progress: portfolio.isEmpty ? 0.2 : 1.0, height: 8)
                            .frame(width: 80)

                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }

                    HStack {
                        Text(portfolio.isEmpty ? "Define your asset split" : "\(portfolio.count) tokens selected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        if portfolio.isEmpty {
                            Text("1/5 Complete")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("+50 XP")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(BrandColors.primary)
                        } else {
                            XPBadge(points: 50)
                        }
                    }
                }
                .gameCardStyle()
            }
        }
    }

    // MARK: - Safety Limits Quest

    private var safetyLimitsQuestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAFETY LIMITS")
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                // Max Per Swap
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max Per Swap")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("\(Int(perSwapLimit))")
                            .font(.title)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                    }

                    GameSlider(value: $perSwapLimit, range: 10...1000, step: 10)
                }
                .gameCardStyle()

                // Daily Max
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Daily Max")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("$")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("\(Int(dailyLimit))")
                            .font(.title)
                            .fontWeight(.heavy)
                            .foregroundColor(.primary)
                    }

                    GameSlider(value: $dailyLimit, range: 100...5000, step: 100)
                }
                .gameCardStyle()
            }
        }
    }

    // MARK: - Main Action Button

    private var mainActionButton: some View {
        Button(action: {
            if hasActiveDelegation {
                Task { await handleRevokeDelegation() }
            } else {
                Task { await handleEnableDelegation() }
            }
        }) {
            HStack {
                if delegationManager.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    if !hasActiveDelegation {
                        Spacer()
                        VStack(spacing: 2) {
                            Text("ENABLE AUTO-PILOT")
                                .font(.title3)
                                .fontWeight(.heavy)

                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                Text("+100 XP")
                                    .fontWeight(.bold)
                            }
                            .font(.caption)
                        }
                        Spacer()
                    } else {
                        Text("Disable Auto-Pilot")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                hasActiveDelegation ?
                LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing) :
                LinearGradient(colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.0, green: 0.4, blue: 0.9)], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundColor(.white)
            .cornerRadius(20)
            .shadow(color: (hasActiveDelegation ? Color.red : Color.blue).opacity(0.4), radius: 10, x: 0, y: 6)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
        }
        .disabled(delegationManager.isLoading || (!hasActiveDelegation && !canEnable))
        .opacity((!hasActiveDelegation && !canEnable) ? 0.6 : 1.0)
    }

    // MARK: - Logic Helpers

    private var hasActiveDelegation: Bool {
        delegationManager.delegationStatus?.hasActiveDelegation ?? false
    }

    private var canEnable: Bool {
        !portfolio.isEmpty && delegationManager.validatePortfolio(portfolio).isValid
    }

    private var completedSteps: Int {
        var count = 0
        if !portfolio.isEmpty { count += 1 }
        // Limits are always "set" to default, but we can count them as done if user interacts?
        // For now let's just count them as done since defaults are valid.
        count += 1
        count += 1 // Duration also has default
        return count
    }

    private var stepsProgress: Double {
        Double(completedSteps) / 3.0
    }

    private func loadDelegationStatus() async {
        await delegationManager.fetchDelegationStatus()
    }

    private func handleEnableDelegation() async {
        guard !delegationManager.isLoading else { return }

        let (isValid, error) = delegationManager.validatePortfolio(portfolio)
        guard isValid else {
            alertMessage = error ?? "Invalid portfolio configuration"
            showAlert = true
            return
        }

        do {
            // Backend creates Privy policy, adds server as additional signer, and activates delegation
            logger.info("📝 Creating delegation with Privy policy...")
            let response = try await delegationManager.approveDelegationV2(
                portfolio: portfolio,
                maxSwapAmountUsd: perSwapLimit,
                dailyLimitUsd: dailyLimit,
                expirationDays: durationDays
            )

            logger.info("✅ Auto-convert enabled successfully!")
            logger.info("   Policy: \(response.policyId)")
            logger.info("   Delegation: \(response.delegationId)")

            // Show success
            HapticManager.shared.success()
            withAnimation { showConfetti = true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            alertMessage = response.message
            showAlert = true

            await loadDelegationStatus()
        } catch {
            logger.error("❌ Failed to enable: \(error)")
            alertMessage = "Failed to enable: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func handleRevokeDelegation() async {
        do {
            // Use Privy V2 revoke (no transaction signature required)
            let message = try await delegationManager.revokeDelegationV2()

            alertMessage = message
            showAlert = true
            await loadDelegationStatus()
        } catch {
            alertMessage = "Failed to revoke: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func broadcastSignedTransaction(_ signedTransaction: String) async throws -> String {
        let callable = FirebaseCallableClient.shared
        let result = try await callable.call(
            "broadcastSignedTransaction",
            data: [
                "signedTransaction": signedTransaction,
                "transactionType": "custom"
            ]
        )
        guard let data = result.data as? [String: Any],
              let txHash = data["transactionHash"] as? String else {
            throw NSError(domain: "AutoConvert", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from server"
            ])
        }
        return txHash
    }
}

#Preview {
    NavigationView {
        AutoConvertSettingsView()
            .environmentObject(HybridPrivyService.shared)
    }
}
