import SwiftUI

struct RecipientSearchField: View {
    @Binding var recipientAddress: String
    @Binding var selectedRecipient: RecentRecipient?
    let recentRecipients: [RecentRecipient]
    let isLoading: Bool
    let onQRScan: () -> Void

    @State private var showingRecents = false
    @State private var lastAddress = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.body)

                TextField("Name, email, or address", text: $recipientAddress)
                    .font(.body)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(isLoading)
                    .focused($isTextFieldFocused)
                    .onAppear {
                        lastAddress = recipientAddress
                    }
                    .onReceive([recipientAddress].publisher.first()) { newValue in
                        // Clear selected recipient if user types manually
                        if newValue != lastAddress && selectedRecipient?.address != newValue {
                            selectedRecipient = nil
                        }
                        lastAddress = newValue
                    }

                if !recipientAddress.isEmpty {
                    Button(action: {
                        recipientAddress = ""
                        selectedRecipient = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: onQRScan) {
                    Image(systemName: "qrcode.viewfinder")
                        .foregroundColor(BrandColors.primary)
                        .font(.title3)
                }
                .disabled(isLoading)
            }
            .padding(16)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            // Selected Recipient Display
            if let recipient = selectedRecipient {
                selectedRecipientCard(recipient)
            }

            // Recent Recipients Dropdown (shows when focused)
            if isTextFieldFocused && !recentRecipients.isEmpty && selectedRecipient == nil {
                recentRecipientsDropdown
            }
            // Recent Recipients Chips (shows when not focused and no input)
            else if !isTextFieldFocused && !recentRecipients.isEmpty && recipientAddress.isEmpty && selectedRecipient == nil {
                recentRecipientsSection
            }
        }
    }

    // MARK: - Selected Recipient Card

    private func selectedRecipientCard(_ recipient: RecentRecipient) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(BrandColors.primary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(recipient.initials)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(BrandColors.primary)
                )

            // Name & Address
            VStack(alignment: .leading, spacing: 4) {
                if let name = recipient.displayName {
                    Text(name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }

                Text(recipient.formattedAddress)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Recent Recipients Dropdown

    private var filteredRecipients: [RecentRecipient] {
        if recipientAddress.isEmpty {
            return Array(recentRecipients.prefix(5))
        } else {
            // Filter by display name or address
            return recentRecipients.filter { recipient in
                if let name = recipient.displayName {
                    return name.localizedCaseInsensitiveContains(recipientAddress)
                }
                return recipient.address.localizedCaseInsensitiveContains(recipientAddress)
            }.prefix(5).map { $0 }
        }
    }

    private var recentRecipientsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredRecipients) { recipient in
                Button(action: {
                    selectRecipient(recipient)
                    isTextFieldFocused = false
                }) {
                    HStack(spacing: 12) {
                        // Avatar
                        Circle()
                            .fill(BrandColors.primary.opacity(0.2))
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(recipient.initials)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(BrandColors.primary)
                            )

                        // Name & Address
                        VStack(alignment: .leading, spacing: 4) {
                            if let name = recipient.displayName {
                                Text(name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                            }

                            Text(recipient.formattedAddress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .font(.system(.caption, design: .monospaced))
                        }

                        Spacer()
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                if recipient.id != filteredRecipients.last?.id {
                    Divider()
                }
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Recent Recipients Section

    private var recentRecipientsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentRecipients.prefix(5)) { recipient in
                        RecentRecipientChip(recipient: recipient) {
                            selectRecipient(recipient)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func selectRecipient(_ recipient: RecentRecipient) {
        selectedRecipient = recipient
        recipientAddress = recipient.address
    }
}

// MARK: - Recent Recipient Chip

struct RecentRecipientChip: View {
    let recipient: RecentRecipient
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Avatar Circle
                Circle()
                    .fill(BrandColors.primary.opacity(0.2))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(recipient.initials)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(BrandColors.primary)
                    )

                // Display Name or Formatted Address
                Text(recipient.displayName ?? recipient.formattedAddress)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 70)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    VStack {
        RecipientSearchField(
            recipientAddress: .constant(""),
            selectedRecipient: .constant(nil),
            recentRecipients: [
                RecentRecipient(
                    id: "1",
                    address: "9XmW7KpL3Rt5QnH8Yz2Vb4Cd6Ef1Gh0Jk9Lm8Nq7Rp2",
                    displayName: "Alice Johnson",
                    lastSentAt: Date(),
                    frequency: 5,
                    tokenType: "SOL"
                ),
                RecentRecipient(
                    id: "2",
                    address: "5Yz2Vb4Cd6Ef1Gh0Jk9Lm8Nq7Rp2St3Uv4Wx5Yz6Za7",
                    displayName: "Bob Smith",
                    lastSentAt: Date(),
                    frequency: 3,
                    tokenType: "USDC"
                )
            ],
            isLoading: false,
            onQRScan: {}
        )
        .padding()
    }
}
