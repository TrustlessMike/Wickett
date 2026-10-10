import SwiftUI

/// Payment preferences settings view for currency and portfolio allocation
struct PaymentPreferencesView: View {
    @StateObject private var preferencesService = UserPreferencesService.shared
    @State private var editedPortfolio: [LegacyPortfolioAllocation] = []
    @State private var showAddTokenSheet = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        Form {
            // Currency Selection
            Section {
                Picker("Local Currency", selection: binding(for: \.localCurrency)) {
                    ForEach(FiatCurrency.allCases) { currency in
                        HStack {
                            Text(currency.symbol)
                                .frame(width: 30)
                            Text(currency.displayName)
                        }
                        .tag(currency)
                    }
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Your preferred currency for payment requests")
            }

            // Portfolio Allocation
            Section {
                ForEach($editedPortfolio) { $allocation in
                    HStack {
                        // Token symbol
                        Text(allocation.token)
                            .font(.headline)
                            .frame(width: 60, alignment: .leading)

                        // Percentage slider
                        Slider(value: $allocation.percentage, in: 0...100, step: 5)

                        // Percentage display
                        Text(allocation.formattedPercentage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .onDelete(perform: deleteAllocation)

                // Add token button
                Button(action: { showAddTokenSheet = true }) {
                    Label("Add Token", systemImage: "plus.circle.fill")
                        .foregroundColor(BrandColors.primary)
                }

                // Portfolio validation status
                if !isPortfolioValid {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Total must equal 100% (currently \(totalPercentage, specifier: "%.1f")%)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Portfolio is valid")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } header: {
                Text("Portfolio Allocation")
            } footer: {
                Text("How you want to receive payments. Must total 100%.")
            }

            // Preferred Payment Token
            Section {
                Picker("Preferred Token", selection: binding(for: \.preferredPaymentToken)) {
                    Text("None").tag(nil as String?)
                    ForEach(TokenRegistry.allTokens, id: \.symbol) { token in
                        Text(token.symbol).tag(token.symbol as String?)
                    }
                }
            } header: {
                Text("Payment Method")
            } footer: {
                Text("Your preferred token when paying others")
            }

            // Save Button
            Section {
                Button(action: savePreferences) {
                    if isSaving {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Saving...")
                        }
                    } else {
                        Text("Save Preferences")
                            .frame(maxWidth: .infinity)
                            .font(.headline)
                    }
                }
                .disabled(!isPortfolioValid || isSaving)
            }
        }
        .navigationTitle("Payment Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadPreferences()
        }
        .sheet(isPresented: $showAddTokenSheet) {
            AddTokenSheet(portfolio: $editedPortfolio)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Helpers

    private func binding<T>(for keyPath: WritableKeyPath<UserPreferences, T>) -> Binding<T> {
        Binding(
            get: { preferencesService.preferences[keyPath: keyPath] },
            set: { newValue in
                var updated = preferencesService.preferences
                updated[keyPath: keyPath] = newValue
                preferencesService.preferences = updated
            }
        )
    }

    private func loadPreferences() {
        editedPortfolio = preferencesService.preferences.portfolio
    }

    private func savePreferences() {
        guard isPortfolioValid else {
            errorMessage = "Portfolio must total 100%"
            showError = true
            return
        }

        isSaving = true

        Task {
            var updated = preferencesService.preferences
            updated.portfolio = editedPortfolio

            await preferencesService.savePreferences(updated)

            await MainActor.run {
                isSaving = false
            }
        }
    }

    private func deleteAllocation(at offsets: IndexSet) {
        editedPortfolio.remove(atOffsets: offsets)
    }

    private var isPortfolioValid: Bool {
        abs(totalPercentage - 100.0) < 0.01
    }

    private var totalPercentage: Double {
        editedPortfolio.reduce(0.0) { $0 + $1.percentage }
    }
}

// MARK: - Add Token Sheet

struct AddTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var portfolio: [LegacyPortfolioAllocation]
    @State private var selectedToken: SolanaToken = TokenRegistry.SOL
    @State private var percentage: Double = 0

    var availableTokens: [SolanaToken] {
        let usedTokens = Set(portfolio.map { $0.token })
        return TokenRegistry.allTokens.filter { !usedTokens.contains($0.symbol) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Picker("Token", selection: $selectedToken) {
                        ForEach(availableTokens, id: \.symbol) { token in
                            HStack {
                                Text(token.symbol)
                                    .font(.headline)
                                Text(token.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(token)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Percentage")
                        Spacer()
                        Text("\(Int(percentage))%")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $percentage, in: 0...100, step: 5)
                } footer: {
                    Text("Adjust other allocations to make total 100%")
                }

                Section {
                    Button("Add Token") {
                        let allocation = LegacyPortfolioAllocation(
                            token: selectedToken.symbol,
                            percentage: percentage
                        )
                        portfolio.append(allocation)
                        dismiss()
                    }
                    .disabled(percentage == 0)
                }
            }
            .navigationTitle("Add Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        PaymentPreferencesView()
    }
}
