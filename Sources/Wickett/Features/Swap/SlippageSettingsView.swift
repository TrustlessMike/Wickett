import SwiftUI

struct SlippageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var slippageBps: Int
    let onUpdate: (Int) -> Void

    @State private var customSlippage: String = ""
    @State private var selectedPreset: Int?

    // Common slippage presets in basis points
    private let presets = [
        (label: "0.1%", bps: 10),
        (label: "0.5%", bps: 50),
        (label: "1%", bps: 100),
        (label: "3%", bps: 300)
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Info Section
                    infoSection

                    // Preset Buttons
                    presetsSection

                    // Custom Input
                    customSection

                    // Warning if high slippage
                    if slippageBps > 100 {
                        warningSection
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Slippage Tolerance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        applySlippage()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(BrandColors.primary)
                }
            }
            .onAppear {
                // Initialize selected preset if current slippage matches
                if let preset = presets.first(where: { $0.bps == slippageBps }) {
                    selectedPreset = preset.bps
                } else {
                    // Custom value
                    customSlippage = formatSlippageForDisplay(slippageBps)
                }
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundColor(BrandColors.primary)

                Text("About Slippage")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Text("Slippage tolerance is the maximum price change you're willing to accept. Higher slippage means your transaction is more likely to succeed, but you may receive less favorable rates.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(BrandColors.primary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Presets Section

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Select")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(presets, id: \.bps) { preset in
                    presetButton(label: preset.label, bps: preset.bps)
                }
            }
        }
    }

    private func presetButton(label: String, bps: Int) -> some View {
        Button(action: {
            selectedPreset = bps
            slippageBps = bps
            customSlippage = ""
        }) {
            VStack(spacing: 8) {
                Text(label)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(selectedPreset == bps ? .white : .primary)

                Text("\(bps) bps")
                    .font(.caption)
                    .foregroundColor(selectedPreset == bps ? .white.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                selectedPreset == bps ? BrandColors.primary : Color(UIColor.secondarySystemBackground)
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        selectedPreset == bps ? BrandColors.primary : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Custom Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            HStack {
                TextField("Enter custom %", text: $customSlippage)
                    .keyboardType(.decimalPad)
                    .font(.body)
                    .padding(16)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .onChange(of: customSlippage) { newValue in
                        selectedPreset = nil
                        if let percentage = Double(newValue) {
                            slippageBps = Int(percentage * 100)
                        }
                    }

                Text("%")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
            }

            if !customSlippage.isEmpty, let percentage = Double(customSlippage) {
                Text("= \(Int(percentage * 100)) basis points")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Warning Section

    private var warningSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("High Slippage Warning")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Slippage above 1% may result in unfavorable rates. Only use high slippage for tokens with low liquidity.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func applySlippage() {
        onUpdate(slippageBps)
    }

    private func formatSlippageForDisplay(_ bps: Int) -> String {
        let percentage = Double(bps) / 100.0
        return String(format: "%.2f", percentage)
    }
}

// MARK: - Preview

#Preview {
    SlippageSettingsView(
        slippageBps: .constant(50),
        onUpdate: { bps in
            print("Updated slippage to \(bps) bps")
        }
    )
}
