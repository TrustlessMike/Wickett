import SwiftUI

struct SwapView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SwapViewModel()
    @State private var showFromTokenSelector = false
    @State private var showToTokenSelector = false
    @State private var showSlippageSettings = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Swap Token Cards (From → To)
                    swapSection

                    // Quote Information Card
                    if viewModel.isRefreshingQuote && viewModel.currentQuote == nil {
                        SkeletonQuoteCard()
                    } else if let quote = viewModel.currentQuote {
                        quoteCard(quote)
                            .opacity(viewModel.isRefreshingQuote ? 0.6 : 1.0)
                    }

                    // Error Message
                    if let error = viewModel.errorMessage {
                        errorSection(error)
                    }

                    // Swap Button
                    swapButton

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Convert")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.transactionState == .completed {
                        Button("Done") {
                            dismiss()
                        }
                    } else {
                        Button(action: { showSlippageSettings = true }) {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(BrandColors.primary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showFromTokenSelector) {
                SwapTokenSelectorSheet(
                    title: "Swap From",
                    selectedToken: $viewModel.fromToken,
                    excludedToken: viewModel.toToken,
                    availableBalances: viewModel.walletService.balances,
                    onSelect: { token in
                        viewModel.updateFromToken(token)
                    }
                )
            }
            .sheet(isPresented: $showToTokenSelector) {
                SwapTokenSelectorSheet(
                    title: "Swap To",
                    selectedToken: $viewModel.toToken,
                    excludedToken: viewModel.fromToken,
                    availableBalances: [],
                    onSelect: { token in
                        viewModel.updateToToken(token)
                    }
                )
            }
            .sheet(isPresented: $showSlippageSettings) {
                SlippageSettingsView(
                    slippageBps: $viewModel.slippageBps,
                    onUpdate: { bps in
                        viewModel.updateSlippage(bps)
                    }
                )
            }
            .overlay {
                if viewModel.isLoading || viewModel.transactionState == .completed {
                    LoadingOverlay(
                        message: loadingMessage,
                        isSuccess: viewModel.transactionState == .completed
                    )
                }
            }
            .onAppear {
                viewModel.initializeWithUserBalances()
                viewModel.startQuoteRefresh()
            }
            .onDisappear {
                viewModel.stopQuoteRefresh()
            }
        }
    }

    // MARK: - Loading Message

    private var loadingMessage: String {
        if viewModel.transactionState == .completed {
            return "Swap completed ✓"
        } else {
            return viewModel.transactionState.displayMessage
        }
    }

    // MARK: - Swap Section

    private var swapSection: some View {
        VStack(spacing: 0) {
            // FROM Token Card
            fromTokenCard
                .id("from-\(viewModel.fromToken.symbol)")

            // Swap Arrow Button
            swapArrowButton
                .padding(.vertical, -20)
                .zIndex(1)

            // TO Token Card
            toTokenCard
                .id("to-\(viewModel.toToken.symbol)")
        }
    }

    // MARK: - From Token Card

    private var fromTokenCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("From")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                if let balance = viewModel.fromTokenBalance {
                    Button(action: { viewModel.setMaxAmount() }) {
                        Text("Max: \(formatBalance(balance, for: viewModel.fromToken))")
                            .font(.caption)
                            .foregroundColor(BrandColors.primary)
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Token Selector
            Button(action: { showFromTokenSelector = true }) {
                HStack(spacing: 12) {
                    TokenImageView(token: viewModel.fromToken, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.fromToken.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(viewModel.fromToken.symbol)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isLoading)

            Divider()

            // Amount Input
            HStack {
                TextField("0.00", text: $viewModel.fromAmount)
                    .font(.system(size: 28, weight: .semibold))
                    .keyboardType(.decimalPad)
                    .disabled(viewModel.isLoading)
                    .onChange(of: viewModel.fromAmount) { newValue in
                        viewModel.updateAmount(newValue)
                    }

                Text(viewModel.fromToken.symbol)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Swap Arrow Button

    private var swapArrowButton: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                viewModel.swapTokens()
            }
        }) {
            ZStack {
                Circle()
                    .fill(BrandColors.primary)
                    .frame(width: 48, height: 48)

                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .disabled(viewModel.isLoading)
        .shadow(color: BrandColors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    // MARK: - To Token Card

    private var toTokenCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("To")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Token Selector
            Button(action: { showToTokenSelector = true }) {
                HStack(spacing: 12) {
                    TokenImageView(token: viewModel.toToken, size: 40)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.toToken.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Text(viewModel.toToken.symbol)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isLoading)

            Divider()

            // Output Amount Display
            HStack {
                if viewModel.isRefreshingQuote {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let output = viewModel.estimatedOutputAmount {
                    Text(output)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.primary)
                } else {
                    Text("0.00")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(viewModel.toToken.symbol)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }

    // MARK: - Quote Card

    private func quoteCard(_ quote: JupiterQuote) -> some View {
        VStack(spacing: 16) {
            // Exchange Rate
            if let rateText = viewModel.exchangeRateText {
                quoteRow(
                    icon: "arrow.2.squarepath",
                    title: "Rate",
                    value: rateText,
                    valueColor: .primary
                )
            }

            Divider()

            // Price Impact
            if let impactText = viewModel.priceImpactText {
                quoteRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Price Impact",
                    value: impactText,
                    valueColor: viewModel.priceImpactColor
                )
            }

            Divider()

            // Minimum Received
            if let minAmount = viewModel.minimumOutputAmount {
                quoteRow(
                    icon: "arrow.down.circle",
                    title: "Minimum Received",
                    value: "\(minAmount) \(viewModel.toToken.symbol)",
                    valueColor: .primary
                )
            }

            Divider()

            // Slippage Tolerance
            quoteRow(
                icon: "slider.horizontal.3",
                title: "Slippage Tolerance",
                value: String(format: "%.2f%%", Double(viewModel.slippageBps) / 100),
                valueColor: .primary
            )
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func quoteRow(icon: String, title: String, value: String, valueColor: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding(16)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Swap Button

    private var swapButton: some View {
        Button(action: {
            Task {
                await viewModel.executeSwap()
            }
        }) {
            HStack {
                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "arrow.2.squarepath")
                    Text(swapButtonText)
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(viewModel.canSwap ? BrandColors.primary : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!viewModel.canSwap)
    }

    private var swapButtonText: String {
        if !viewModel.hasSufficientBalance {
            return "Insufficient Balance"
        } else if viewModel.fromToken == viewModel.toToken {
            return "Select Different Tokens"
        } else if viewModel.currentQuote == nil {
            return "Enter Amount"
        } else {
            return "Review Swap"
        }
    }

    // MARK: - Helper Functions

    private func formatBalance(_ balance: Decimal, for token: SolanaToken) -> String {
        let number = NSDecimalNumber(decimal: balance).doubleValue

        if number >= 1000 {
            return String(format: "%.2f", number)
        } else if number >= 1 {
            return String(format: "%.4f", number)
        } else {
            return String(format: "%.6f", number)
        }
    }
}

// MARK: - Swap Token Selector Sheet

struct SwapTokenSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @Binding var selectedToken: SolanaToken
    let excludedToken: SolanaToken?
    let availableBalances: [TokenBalance]
    let onSelect: (SolanaToken) -> Void

    // MARK: - Computed Properties

    private var allTokens: [SolanaToken] {
        TokenRegistry.allTokens.filter { token in
            // Exclude the other token in the swap pair
            if let excluded = excludedToken, token.symbol == excluded.symbol {
                return false
            }
            // If no balances provided, show all tokens (for TO selector)
            // Otherwise only show tokens with balance (for FROM selector)
            if availableBalances.isEmpty {
                return true
            }
            return availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    private var mainTokens: [SolanaToken] {
        TokenRegistry.mainTokens.filter { token in
            if let excluded = excludedToken, token.symbol == excluded.symbol {
                return false
            }
            // If no balances provided, show all tokens (for TO selector)
            // Otherwise only show tokens with balance (for FROM selector)
            if availableBalances.isEmpty {
                return true
            }
            return availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    private var defiTokens: [SolanaToken] {
        TokenRegistry.defiTokens.filter { token in
            if let excluded = excludedToken, token.symbol == excluded.symbol {
                return false
            }
            // If no balances provided, show all tokens (for TO selector)
            // Otherwise only show tokens with balance (for FROM selector)
            if availableBalances.isEmpty {
                return true
            }
            return availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    private var xStockTokens: [SolanaToken] {
        TokenRegistry.xStockTokens.filter { token in
            if let excluded = excludedToken, token.symbol == excluded.symbol {
                return false
            }
            // If no balances provided, show all tokens (for TO selector)
            // Otherwise only show tokens with balance (for FROM selector)
            if availableBalances.isEmpty {
                return true
            }
            return availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    var body: some View {
        NavigationView {
            List {
                // Main Tokens Section
                if !mainTokens.isEmpty {
                    Section {
                        ForEach(mainTokens) { token in
                            tokenRow(for: token)
                        }
                    } header: {
                        Text("Main Tokens")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }

                // DeFi Tokens Section
                if !defiTokens.isEmpty {
                    Section {
                        ForEach(defiTokens) { token in
                            tokenRow(for: token)
                        }
                    } header: {
                        Text("DeFi Tokens")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }

                // xStocks Section
                if !xStockTokens.isEmpty {
                    Section {
                        ForEach(xStockTokens) { token in
                            tokenRow(for: token)
                        }
                    } header: {
                        Text("xStocks")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .textCase(nil)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Token Row Helper

    private func tokenRow(for token: SolanaToken) -> some View {
        Button(action: {
            selectedToken = token
            onSelect(token)
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Token Icon
                TokenImageView(token: token, size: 40)

                // Token Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(token.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text(token.symbol)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        // Show balance if available
                        if let balance = availableBalances.first(where: { $0.token.symbol == token.symbol }) {
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(balance.displayAmount)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Checkmark if selected
                if selectedToken.symbol == token.symbol {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(BrandColors.primary)
                        .font(.title3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    SwapView()
}
