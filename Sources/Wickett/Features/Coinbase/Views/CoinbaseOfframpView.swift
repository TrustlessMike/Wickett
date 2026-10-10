import SwiftUI

struct CoinbaseOfframpView: View {
    @StateObject private var viewModel = CoinbaseOfframpViewModel()
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
                            Image(systemName: "banknote.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)

                            Text("Cash Out")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Withdraw funds to your bank")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 32)

                        // Balance Display
                        VStack(spacing: 8) {
                            Text("Available Balance")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(alignment: .center, spacing: 8) {
                                Image("TokenUSDC")
                                    .resizable()
                                    .frame(width: 24, height: 24)

                                Text(viewModel.formattedUsdcBalance)
                                    .font(.title)
                                    .fontWeight(.bold)

                                Text("USDC")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Amount Input Card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Amount to Cash Out")
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
                                maxButton
                            }

                            // Insufficient balance warning
                            if !viewModel.hasSufficientBalance && viewModel.parsedFiatAmount != nil {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text("Insufficient USDC balance")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Status Messages
                        if viewModel.state == .awaitingTransfer, let session = viewModel.currentSession {
                            transferInstructionsCard(depositAddress: session.depositAddress)
                        } else if viewModel.state == .pollingStatus {
                            statusCard(
                                icon: "arrow.clockwise",
                                title: "Processing...",
                                message: "Waiting for your withdrawal to complete. This may take a few minutes.",
                                color: .blue
                            )
                        } else if viewModel.state == .completed {
                            statusCard(
                                icon: "checkmark.circle.fill",
                                title: "Success!",
                                message: "Your withdrawal is complete. Funds will arrive in your bank account shortly.",
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
                            infoRow(icon: "lock.shield.fill", text: "Secure withdrawal powered by Coinbase")
                            infoRow(icon: "building.columns.fill", text: "Funds arrive in 1-3 business days")
                            infoRow(icon: "dollarsign.circle.fill", text: "Competitive exchange rates")
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
            .navigationTitle("Cash Out")
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
            .alert("Send USDC", isPresented: $viewModel.showTransferPrompt) {
                Button("I'll Send Manually", role: .none) {
                    viewModel.confirmTransferIntent()
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancel()
                }
            } message: {
                if let session = viewModel.currentSession {
                    Text("To complete your withdrawal, send \(viewModel.formattedAmount) USDC to:\n\n\(session.depositAddress)\n\nOnce sent, your bank will receive the funds in 1-3 business days.")
                }
            }
        }
    }

    // MARK: - Action Button

    @ViewBuilder
    private var actionButton: some View {
        Button(action: {
            handleActionButton()
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

    private func handleActionButton() {
        switch viewModel.state {
        case .idle, .failed:
            Task {
                await viewModel.startOfframp()
            }
        case .completed:
            dismiss()
        default:
            break
        }
    }

    private var actionButtonText: String {
        switch viewModel.state {
        case .idle, .failed:
            return "Continue"
        case .completed:
            return "Done"
        case .pollingStatus, .awaitingTransfer:
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
            return viewModel.canStartOfframp && viewModel.hasSufficientBalance
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

    private var maxButton: some View {
        Button(action: {
            if let balance = viewModel.usdcBalance {
                let maxAmount = NSDecimalNumber(decimal: balance).doubleValue
                viewModel.fiatAmount = String(format: "%.2f", maxAmount)
            }
        }) {
            Text("Max")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(8)
        }
        .disabled(viewModel.state != .idle || viewModel.usdcBalance == nil)
    }

    private func transferInstructionsCard(depositAddress: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Send USDC")
                    .font(.headline)
                    .foregroundColor(.blue)
            }

            Text("Send \(viewModel.formattedAmount) USDC to the address below:")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text(depositAddress)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Button(action: {
                    UIPasteboard.general.string = depositAddress
                }) {
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(8)

            Text("Note: You can copy this address and send from your wallet manually, or use the Send feature in Wickett.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
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
    CoinbaseOfframpView()
}
