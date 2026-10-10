import SwiftUI

struct SendView: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SendViewModel
    @State private var showTokenSelector = false
    @State private var showRecipientSearch = false
    @FocusState private var isMemoFocused: Bool

    init(user: User) {
        self.user = user
        _viewModel = StateObject(wrappedValue: SendViewModel(userWalletAddress: user.walletAddress))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Spacer()

            // Recipient Section
            recipientSection
                .padding(.bottom, 24)

            // Amount Display
            amountDisplay

            // Token Selector Pill
            tokenSelectorPill
                .padding(.top, 12)

            Spacer()

            // Memo Field
            memoField
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Error Message
            if let error = viewModel.displayError {
                errorBanner(error)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            // Send Button
            sendButton
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Custom Numpad
            numpad
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showRecipientSearch) {
            SendRecipientSearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showTokenSelector) {
            TokenSelectorSheet(
                selectedToken: $viewModel.selectedToken,
                availableBalances: viewModel.walletService.balances
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
    }

    // MARK: - Loading Message

    private var loadingMessage: String {
        if viewModel.transactionState == .completed {
            if let recipient = viewModel.selectedRecipient, let name = recipient.displayName {
                if let formatted = formatAmount() {
                    return "Sent \(formatted) to \(name) ✓"
                }
                return "Sent to \(name) ✓"
            }
            return "Transaction sent ✓"
        } else {
            if let recipient = viewModel.selectedRecipient, let name = recipient.displayName {
                if let formatted = formatAmount() {
                    return "Sending \(formatted) to \(name)..."
                }
                return "Sending to \(name)..."
            }
            return viewModel.transactionState.displayMessage
        }
    }

    private func formatAmount() -> String? {
        guard !viewModel.usdAmount.isEmpty,
              let decimal = Decimal(string: viewModel.usdAmount) else {
            return nil
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: decimal as NSDecimalNumber)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.primary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Recipient Section

    private var recipientSection: some View {
        VStack(spacing: 8) {
            Button(action: { showRecipientSearch = true }) {
                ZStack {
                    if let recipient = viewModel.selectedRecipient {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text((recipient.displayName ?? "?").prefix(1).uppercased())
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.primary)
                            )
                    } else {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 36))
                                    .foregroundColor(.gray)
                            )

                        // Plus badge
                        Circle()
                            .fill(BrandColors.primary)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 28, y: 28)
                    }
                }
            }

            // Recipient name or prompt
            if let recipient = viewModel.selectedRecipient {
                HStack(spacing: 4) {
                    Text(recipient.displayName ?? String(recipient.address.prefix(8)) + "...")
                        .font(.headline)

                    Button(action: {
                        viewModel.selectedRecipient = nil
                        viewModel.recipientAddress = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Add Recipient")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Amount Display

    private var amountDisplay: some View {
        HStack(spacing: 4) {
            Text("$")
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(viewModel.usdAmount.isEmpty ? .gray : .primary)

            Text(viewModel.usdAmount.isEmpty ? "0" : viewModel.usdAmount)
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(viewModel.usdAmount.isEmpty ? .gray : .primary)

            if !viewModel.usdAmount.isEmpty {
                Button(action: {
                    viewModel.usdAmount = ""
                    viewModel.cryptoAmount = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Token Selector Pill

    private var tokenSelectorPill: some View {
        Button(action: { showTokenSelector = true }) {
            HStack(spacing: 6) {
                TokenImageView(token: viewModel.selectedToken, size: 20)

                Text(viewModel.selectedToken.symbol)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .cornerRadius(20)
        }
        .foregroundColor(.primary)
    }

    // MARK: - Memo Field

    private var memoField: some View {
        HStack {
            TextField("What's this for?", text: $viewModel.memo)
                .focused($isMemoFocused)
                .font(.body)

            if isMemoFocused {
                Button("Done") {
                    isMemoFocused = false
                }
                .font(.subheadline.bold())
                .foregroundColor(BrandColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.subheadline)

            Text(error)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Send Button

    private var sendButton: some View {
        Button(action: {
            Task {
                await viewModel.sendTransaction()
            }
        }) {
            HStack {
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(sendButtonText)
                        .font(.headline)
                }
                Spacer()
            }
            .padding(.vertical, 16)
            .background(canSend ? BrandColors.primary : Color(.systemGray4))
            .foregroundColor(.white)
            .cornerRadius(28)
        }
        .disabled(viewModel.isLoading || !canSend)
    }

    private var sendButtonText: String {
        if !viewModel.usdAmount.isEmpty, let decimal = Decimal(string: viewModel.usdAmount), decimal > 0 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.maximumFractionDigits = 2
            if let formatted = formatter.string(from: decimal as NSDecimalNumber) {
                return "Send \(formatted)"
            }
        }
        return "Send"
    }

    private var canSend: Bool {
        guard viewModel.selectedRecipient != nil || !viewModel.recipientAddress.isEmpty,
              !viewModel.usdAmount.isEmpty,
              let amount = Decimal(string: viewModel.usdAmount),
              amount > 0,
              viewModel.transactionState == .idle else {
            return false
        }
        return true
    }

    // MARK: - Numpad

    private var numpad: some View {
        VStack(spacing: 8) {
            ForEach(numpadRows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        numpadButton(key)
                    }
                }
            }
        }
    }

    private let numpadRows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        [".", "0", "⌫"]
    ]

    private func numpadButton(_ key: String) -> some View {
        Button(action: { handleNumpadTap(key) }) {
            Text(key)
                .font(.system(size: 28, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(.systemBackground))
                .foregroundColor(.primary)
                .cornerRadius(12)
        }
    }

    private func handleNumpadTap(_ key: String) {
        switch key {
        case "⌫":
            if !viewModel.usdAmount.isEmpty {
                viewModel.usdAmount.removeLast()
                updateCryptoAmount()
            }
        case ".":
            if !viewModel.usdAmount.contains(".") {
                viewModel.usdAmount += viewModel.usdAmount.isEmpty ? "0." : "."
            }
        default:
            // Limit to reasonable amount (max 999,999.99)
            if viewModel.usdAmount.count < 10 {
                // Only allow 2 decimal places
                if let dotIndex = viewModel.usdAmount.firstIndex(of: ".") {
                    let decimals = viewModel.usdAmount.distance(from: dotIndex, to: viewModel.usdAmount.endIndex) - 1
                    if decimals >= 2 { return }
                }
                viewModel.usdAmount += key
                updateCryptoAmount()
            }
        }
    }

    private func updateCryptoAmount() {
        guard let usdDecimal = Decimal(string: viewModel.usdAmount),
              viewModel.currentUSDPrice > 0 else {
            viewModel.cryptoAmount = ""
            return
        }
        let cryptoDecimal = usdDecimal / viewModel.currentUSDPrice
        viewModel.cryptoAmount = String(describing: cryptoDecimal)
    }
}

// MARK: - Recipient Search Sheet

struct SendRecipientSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SendViewModel
    @State private var searchQuery = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search by @username, name, or wallet", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: searchQuery) { newValue in
                            viewModel.searchUsers(query: newValue)
                        }

                    if viewModel.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                            viewModel.clearSearch()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()

                // Content
                List {
                    // Suggested Recipients (horizontal chips) - only show when not searching
                    if searchQuery.isEmpty && !viewModel.suggestedRecipients.isEmpty {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 16) {
                                    ForEach(viewModel.suggestedRecipients) { recipient in
                                        suggestedChip(recipient)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                            .listRowBackground(Color.clear)
                        } header: {
                            Text("Suggested")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Search Results (when searching)
                    if !searchQuery.isEmpty && !viewModel.searchResults.isEmpty {
                        Section("Results") {
                            ForEach(viewModel.searchResults) { result in
                                Button(action: {
                                    selectSearchResult(result)
                                }) {
                                    searchResultRow(result)
                                }
                            }
                        }
                    }

                    // Recent Recipients (when not searching or no search results)
                    if searchQuery.isEmpty && !viewModel.recentRecipients.isEmpty {
                        Section("Recent") {
                            ForEach(viewModel.recentRecipients) { recipient in
                                Button(action: {
                                    viewModel.selectedRecipient = recipient
                                    viewModel.recipientAddress = recipient.address
                                    dismiss()
                                }) {
                                    recipientRow(recipient)
                                }
                            }
                        }
                    }

                    // No results message
                    if !searchQuery.isEmpty && viewModel.searchResults.isEmpty && !viewModel.isSearching {
                        if searchQuery.count < 2 {
                            Text("Type at least 2 characters to search")
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        } else {
                            Text("No users found for \"\(searchQuery)\"")
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Send To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                viewModel.clearSearch()
            }
        }
    }

    // MARK: - Suggested Chip

    private func suggestedChip(_ recipient: RecentRecipient) -> some View {
        Button(action: {
            viewModel.selectedRecipient = recipient
            viewModel.recipientAddress = recipient.address
            dismiss()
        }) {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(recipient.initials)
                            .font(.headline)
                            .foregroundColor(.primary)
                    )

                Text(recipient.displayName ?? recipient.formattedAddress)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Result Row

    private func searchResultRow(_ result: UserSearchResult) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(String(result.displayName.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundColor(.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                // Show @username if available
                if let username = result.username {
                    Text("@\(username)")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(result.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(result.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }

                // Short wallet address
                Text(shortWallet(result.walletAddress))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }

    private func selectSearchResult(_ result: UserSearchResult) {
        // Convert UserSearchResult to RecentRecipient for selection
        let recipient = RecentRecipient(
            id: result.userId,
            address: result.walletAddress,
            displayName: result.displayName,
            lastSentAt: Date(),
            frequency: 0,
            tokenType: nil
        )
        viewModel.selectedRecipient = recipient
        viewModel.recipientAddress = result.walletAddress
        dismiss()
    }

    private func shortWallet(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }

    // MARK: - Recent Recipient Row

    private func recipientRow(_ recipient: RecentRecipient) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 44, height: 44)
                .overlay(
                    Text(recipient.initials)
                        .font(.headline)
                        .foregroundColor(.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(recipient.displayName ?? "Unknown")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(recipient.formattedAddress)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Token Selector Sheet (keep existing)

struct TokenSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedToken: SolanaToken
    let availableBalances: [TokenBalance]

    private var mainTokensWithBalance: [SolanaToken] {
        TokenRegistry.mainTokens.filter { token in
            availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    private var defiTokensWithBalance: [SolanaToken] {
        TokenRegistry.defiTokens.filter { token in
            availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    private var xStockTokensWithBalance: [SolanaToken] {
        TokenRegistry.xStockTokens.filter { token in
            availableBalances.contains(where: { $0.token.symbol == token.symbol && $0.hasBalance })
        }
    }

    var body: some View {
        NavigationView {
            List {
                if !mainTokensWithBalance.isEmpty {
                    Section {
                        ForEach(mainTokensWithBalance) { token in
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

                if !defiTokensWithBalance.isEmpty {
                    Section {
                        ForEach(defiTokensWithBalance) { token in
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

                if !xStockTokensWithBalance.isEmpty {
                    Section {
                        ForEach(xStockTokensWithBalance) { token in
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
            .navigationTitle("Select Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func tokenRow(for token: SolanaToken) -> some View {
        Button(action: {
            selectedToken = token
            dismiss()
        }) {
            HStack(spacing: 12) {
                TokenImageView(token: token, size: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(token.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if let balance = availableBalances.first(where: { $0.token.symbol == token.symbol }) {
                        Text(balance.displayUSD)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

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
    SendView(
        user: User(
            id: "test",
            email: "test@example.com",
            name: "Test User",
            walletAddress: "ABC123XYZ789ABC123XYZ789ABC123XYZ789ABC123XYZ789",
            username: nil
        )
    )
}
