import SwiftUI

/// Payment method options for Coinbase onramp
enum OnrampPaymentMethod: String, CaseIterable, Identifiable {
    case applePay = "Apple Pay"
    case creditCard = "Credit/Debit Card"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .applePay:
            return "creditcard.fill"
        case .creditCard:
            return "creditcard"
        }
    }

    var description: String {
        switch self {
        case .applePay:
            return "Native Apple Pay (Recommended)"
        case .creditCard:
            return "Coinbase hosted checkout"
        }
    }

    var color: Color {
        switch self {
        case .applePay:
            return .black
        case .creditCard:
            return .blue
        }
    }
}

/// Payment method selector component
struct PaymentMethodSelectorView: View {
    @Binding var selectedMethod: OnrampPaymentMethod

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Payment Method")
                .font(.headline)

            ForEach(OnrampPaymentMethod.allCases) { method in
                paymentMethodRow(method: method)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func paymentMethodRow(method: OnrampPaymentMethod) -> some View {
        Button(action: {
            selectedMethod = method
        }) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: method.icon)
                    .font(.title2)
                    .foregroundColor(method.color)
                    .frame(width: 32)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(method.rawValue)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text(method.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Selection indicator
                if selectedMethod == method {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundColor(.gray)
                        .font(.title3)
                }
            }
            .padding()
            .background(
                selectedMethod == method
                    ? Color.blue.opacity(0.1)
                    : Color(UIColor.tertiarySystemGroupedBackground)
            )
            .cornerRadius(10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PaymentMethodSelectorView(selectedMethod: .constant(.applePay))
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
}
