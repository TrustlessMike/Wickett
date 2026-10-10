import SwiftUI

enum AmountDisplayMode {
    case usd
    case crypto

    mutating func toggle() {
        self = (self == .usd) ? .crypto : .usd
    }
}

struct AmountInputField: View {
    @Binding var usdAmount: String
    @Binding var cryptoAmount: String
    @Binding var displayMode: AmountDisplayMode
    let selectedToken: SolanaToken
    let usdPrice: Decimal
    let availableBalance: TokenBalance?
    let isLoading: Bool
    let onMaxTapped: () -> Void

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Amount")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: onMaxTapped) {
                    Text("MAX")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(BrandColors.primary)
                        .cornerRadius(8)
                }
                .disabled(isLoading || availableBalance == nil)
            }

            // Main Amount Input
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    // Currency Symbol/Prefix
                    Text(displayMode == .usd ? "$" : "")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(displayMode == .usd ? .primary : .clear)

                    // Amount Input
                    TextField(displayMode == .usd ? "0.00" : "0.00", text: displayMode == .usd ? $usdAmount : $cryptoAmount)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .disabled(isLoading)
                        .focused($isAmountFocused)
                        .onChange(of: usdAmount) { newValue in
                            if displayMode == .usd {
                                convertUSDToCrypto(newValue)
                            }
                        }
                        .onChange(of: cryptoAmount) { newValue in
                            if displayMode == .crypto {
                                convertCryptoToUSD(newValue)
                            }
                        }

                    // Token Symbol (for crypto mode)
                    if displayMode == .crypto {
                        Text(selectedToken.symbol)
                            .font(.title)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Toggle Button & Conversion Display
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        displayMode.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.caption)

                        if displayMode == .usd {
                            // Show crypto equivalent
                            Text(cryptoEquivalent)
                                .font(.subheadline)
                        } else {
                            // Show USD equivalent
                            Text(usdEquivalent)
                                .font(.subheadline)
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.tertiarySystemBackground))
                    .cornerRadius(8)
                }
                .disabled(isLoading || usdPrice <= 0)
            }
            .padding(20)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)

            // Quick Amount Buttons (USD only)
            if displayMode == .usd {
                quickAmountButtons
            }

            // Available Balance
            if let balance = availableBalance {
                HStack(spacing: 4) {
                    Text("Available:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(balance.displayAmount)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    if usdPrice > 0, let formatted = formatBalanceUSD(balance: balance) {
                        Text("≈ \(formatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Quick Amount Buttons

    private var quickAmountButtons: some View {
        HStack(spacing: 8) {
            ForEach([10, 25, 50, 100], id: \.self) { amount in
                Button(action: {
                    usdAmount = String(amount)
                    convertUSDToCrypto(String(amount))
                }) {
                    Text("$\(amount)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(BrandColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(BrandColors.primary.opacity(0.1))
                        .cornerRadius(10)
                }
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Computed Properties

    private var cryptoEquivalent: String {
        guard !cryptoAmount.isEmpty, let decimal = Decimal(string: cryptoAmount) else {
            return "≈ 0.00 \(selectedToken.symbol)"
        }
        return "≈ \(formatCryptoAmount(decimal)) \(selectedToken.symbol)"
    }

    private var usdEquivalent: String {
        guard !usdAmount.isEmpty, let decimal = Decimal(string: usdAmount) else {
            return "≈ $0.00"
        }
        return "≈ \(formatUSDAmount(decimal))"
    }

    // MARK: - Conversion Logic

    private func convertUSDToCrypto(_ usdString: String) {
        guard !usdString.isEmpty,
              let usdDecimal = Decimal(string: usdString),
              usdPrice > 0 else {
            cryptoAmount = ""
            return
        }

        let cryptoDecimal = usdDecimal / usdPrice
        cryptoAmount = formatCryptoAmount(cryptoDecimal)
    }

    private func convertCryptoToUSD(_ cryptoString: String) {
        guard !cryptoString.isEmpty,
              let cryptoDecimal = Decimal(string: cryptoString),
              usdPrice > 0 else {
            usdAmount = ""
            return
        }

        let usdDecimal = cryptoDecimal * usdPrice
        usdAmount = formatUSDAmount(usdDecimal)
    }

    // MARK: - Formatting Helpers

    private func formatUSDAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2

        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private func formatCryptoAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = selectedToken.decimals
        formatter.minimumFractionDigits = 2

        return formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
    }

    private func formatBalanceUSD(balance: TokenBalance) -> String? {
        let balanceDecimal = selectedToken.fromLamports(balance.lamports)
        let usdValue = balanceDecimal * usdPrice
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2

        return formatter.string(from: usdValue as NSDecimalNumber)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        AmountInputField(
            usdAmount: .constant("50.00"),
            cryptoAmount: .constant("0.0234"),
            displayMode: .constant(.usd),
            selectedToken: TokenRegistry.SOL,
            usdPrice: 150.00,
            availableBalance: TokenBalance(
                token: TokenRegistry.SOL,
                lamports: 10000000,
                usdPrice: 150.00
            ),
            isLoading: false,
            onMaxTapped: {}
        )
        .padding()
    }
}
