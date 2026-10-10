import SwiftUI

struct CreateRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PaymentRequestViewModel()

    let user: User

    @State private var showRequestCreated = false
    @State private var showRecipientSearch = false
    @FocusState private var isMemoFocused: Bool

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

            Spacer()

            // Memo Field
            memoField
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Action Buttons
            actionButtons
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Custom Numpad
            numpad
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showRecipientSearch) {
            RecipientSearchSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showRequestCreated) {
            if let request = viewModel.createdRequest {
                RequestCreatedView(request: request, qrCodeImage: viewModel.qrCodeImage)
                    .onDisappear {
                        viewModel.resetCreateForm()
                        dismiss()
                    }
            }
        }
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
                        // Show selected recipient avatar
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(recipient.displayName.prefix(1).uppercased())
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.primary)
                            )
                    } else {
                        // Show "add" state
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

            // Recipient name or "Anyone"
            if let recipient = viewModel.selectedRecipient {
                HStack(spacing: 4) {
                    Text(recipient.displayName)
                        .font(.headline)

                    Button(action: {
                        viewModel.selectedRecipient = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Anyone")
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
                .foregroundColor(viewModel.amount.isEmpty ? .gray : .primary)

            Text(viewModel.amount.isEmpty ? "0" : viewModel.amount)
                .font(.system(size: 56, weight: .bold))
                .foregroundColor(viewModel.amount.isEmpty ? .gray : .primary)

            if !viewModel.amount.isEmpty {
                Button(action: { viewModel.amount = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
        }
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

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Request Button
            Button(action: {
                Task {
                    await viewModel.createRequest()
                    if viewModel.createdRequest != nil {
                        showRequestCreated = true
                    }
                }
            }) {
                HStack {
                    Spacer()
                    if viewModel.isCreating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Request")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(isFormValid ? BrandColors.primary : Color(.systemGray4))
                .foregroundColor(.white)
                .cornerRadius(28)
            }
            .disabled(viewModel.isCreating || !isFormValid)

            // Pay Button
            Button(action: {
                // TODO: Navigate to send flow with amount pre-filled
            }) {
                HStack {
                    Spacer()
                    Text("Pay")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(isFormValid ? Color(.label) : Color(.systemGray4))
                .foregroundColor(Color(.systemBackground))
                .cornerRadius(28)
            }
            .disabled(!isFormValid)
        }
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
            if !viewModel.amount.isEmpty {
                viewModel.amount.removeLast()
            }
        case ".":
            if !viewModel.amount.contains(".") {
                viewModel.amount += viewModel.amount.isEmpty ? "0." : "."
            }
        default:
            // Limit to reasonable amount (max 999,999.99)
            if viewModel.amount.count < 10 {
                // Only allow 2 decimal places
                if let dotIndex = viewModel.amount.firstIndex(of: ".") {
                    let decimals = viewModel.amount.distance(from: dotIndex, to: viewModel.amount.endIndex) - 1
                    if decimals >= 2 { return }
                }
                viewModel.amount += key
            }
        }
    }

    // MARK: - Form Validation

    private var isFormValid: Bool {
        guard !viewModel.amount.isEmpty,
              let amount = Decimal(string: viewModel.amount),
              amount > 0 else {
            return false
        }
        return true
    }
}

// MARK: - Recipient Search Sheet

struct RecipientSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PaymentRequestViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search by @username, name, or wallet", text: $viewModel.recipientSearchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: viewModel.recipientSearchQuery) { _ in
                            Task {
                                await viewModel.searchForRecipients()
                            }
                        }

                    if viewModel.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding()

                // Search Results
                List {
                    ForEach(viewModel.searchResults, id: \.userId) { result in
                        Button(action: {
                            viewModel.selectedRecipient = result
                            viewModel.searchResults = []
                            viewModel.recipientSearchQuery = ""
                            dismiss()
                        }) {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(.systemGray4))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(result.displayName.prefix(1).uppercased())
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.primaryIdentifier)
                                        .font(.body)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)

                                    if result.username != nil {
                                        Text(result.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text(result.walletAddress)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }

                    if viewModel.searchResults.isEmpty && !viewModel.recipientSearchQuery.isEmpty && !viewModel.isSearching {
                        Text("No users found")
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Add Recipient")
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
}

#Preview {
    CreateRequestView(user: User(
        id: "test",
        email: "test@example.com",
        name: "Test User",
        walletAddress: "TestWallet123",
        username: nil
    ))
}
