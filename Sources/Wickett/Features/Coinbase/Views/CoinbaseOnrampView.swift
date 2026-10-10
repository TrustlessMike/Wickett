import SwiftUI

struct CoinbaseOnrampView: View {
    @StateObject private var viewModel = CoinbaseOnrampViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "dollarsign.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.green)

                            Text("Buy Crypto")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Add funds to your Wickett wallet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 32)

                        // Amount Input Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Amount")
                                .font(.headline)

                            HStack {
                                Text("$")
                                    .font(.title)
                                    .foregroundColor(.secondary)

                                TextField("0.00", text: $viewModel.fiatAmount)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .keyboardType(.decimalPad)
                                    .disabled(viewModel.state != .idle)
                            }

                            Divider()

                            // Quick amount buttons
                            HStack(spacing: 12) {
                                quickAmountButton(amount: 25)
                                quickAmountButton(amount: 50)
                                quickAmountButton(amount: 100)
                                quickAmountButton(amount: 250)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Asset Info
                        VStack(alignment: .leading, spacing: 12) {
                            Text("You'll receive")
                                .font(.headline)

                            HStack {
                                Image("TokenUSDC")
                                    .resizable()
                                    .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("USDC")
                                        .font(.body)
                                        .fontWeight(.semibold)

                                    Text("USD Coin on Solana")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if let amount = viewModel.parsedFiatAmount {
                                    Text("≈ \(String(format: "%.2f", amount)) USDC")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Payment Method Selector
                        PaymentMethodSelectorView(selectedMethod: $viewModel.selectedPaymentMethod)

                        // Status Messages
                        if viewModel.state == .pollingStatus {
                            statusCard(
                                icon: "arrow.clockwise",
                                title: "Processing...",
                                message: "Waiting for your purchase to complete. This may take a few minutes.",
                                color: .blue
                            )
                        } else if viewModel.state == .completed {
                            statusCard(
                                icon: "checkmark.circle.fill",
                                title: "Success!",
                                message: "Your USDC has been added to your wallet.",
                                color: .green
                            )
                        } else if let error = viewModel.errorMessage {
                            statusCard(
                                icon: "exclamationmark.triangle.fill",
                                title: "Error",
                                message: error,
                                color: .red
                            )
                        }

                        // Info Section
                        VStack(alignment: .leading, spacing: 8) {
                            infoRow(icon: "lock.shield.fill", text: "Secure payment powered by Coinbase")
                            infoRow(icon: "creditcard.fill", text: "Pay with card, Apple Pay, or bank transfer")
                            infoRow(icon: "bolt.fill", text: "Funds typically arrive in minutes")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding()

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal)
                }

                // Action Button (Fixed at bottom)
                VStack {
                    Spacer()

                    actionButton
                        .padding()
                        .background(Color(UIColor.systemGroupedBackground))
                }
            }
            .navigationTitle("Buy Crypto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.cancel()
                        dismiss()
                    }
                    .disabled(viewModel.state == .creatingSession)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if viewModel.state == .creatingSession || viewModel.state == .pollingStatus {
                        ProgressView()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showCheckout) {
                if let session = viewModel.currentSession,
                   let url = URL(string: session.checkoutUrl) {
                    NavigationView {
                        CoinbaseSafariView(url: url) {
                            viewModel.handleCheckoutDismissed()
                        }
                        .navigationTitle("Coinbase Pay")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    viewModel.handleCheckoutDismissed()
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showApplePaySheet) {
                if let order = viewModel.currentApplePayOrder,
                   let url = URL(string: order.paymentLinkUrl) {
                    NavigationView {
                        CoinbaseSafariView(url: url) {
                            viewModel.handleApplePayDismissed()
                        }
                        .navigationTitle("Apple Pay")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    viewModel.handleApplePayDismissed()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        Button(action: {
            Task {
                await viewModel.startOnramp()
            }
        }) {
            HStack {
                if viewModel.state == .creatingSession {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(actionButtonText)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(actionButtonColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(!actionButtonEnabled)
        .opacity(actionButtonEnabled ? 1.0 : 0.5)
    }

    private var actionButtonText: String {
        switch viewModel.state {
        case .idle, .failed:
            return "Continue to Payment"
        case .completed:
            return "Done"
        case .pollingStatus:
            return "Processing..."
        default:
            return "Loading..."
        }
    }

    private var actionButtonColor: Color {
        switch viewModel.state {
        case .completed:
            return .green
        case .failed:
            return .red
        default:
            return .blue
        }
    }

    private var actionButtonEnabled: Bool {
        switch viewModel.state {
        case .idle:
            return viewModel.canStartOnramp && viewModel.parsedFiatAmount != nil
        case .completed:
            return true
        default:
            return false
        }
    }

    // MARK: - Helper Views

    private func quickAmountButton(amount: Int) -> some View {
        Button(action: {
            viewModel.fiatAmount = "\(amount)"
        }) {
            Text("$\(amount)")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color(UIColor.tertiarySystemGroupedBackground))
                .foregroundColor(.primary)
                .cornerRadius(8)
        }
        .disabled(viewModel.state != .idle)
    }

    private func statusCard(icon: String, title: String, message: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
            Text(text)
        }
    }
}

#Preview {
    CoinbaseOnrampView()
}
