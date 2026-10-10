import SwiftUI

struct TermsAcceptanceView: View {
    @Binding var hasAccepted: Bool
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            // Progress indicator
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                Spacer()
            }
            .padding(.horizontal)

            Spacer()

            // Icon
            Image(systemName: "doc.text.fill")
                .font(.system(size: 80))
                .foregroundColor(BrandColors.primary)

            // Title
            Text("Terms & Privacy")
                .font(.title)
                .fontWeight(.bold)

            Text("Please review and accept to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Terms Links
            VStack(spacing: 16) {
                Link(destination: URL(string: AppConfiguration.Legal.termsOfServiceURL)!) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(BrandColors.primary)
                            .frame(width: 24)
                        Text("Terms of Service")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }

                Link(destination: URL(string: AppConfiguration.Legal.privacyPolicyURL)!) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(BrandColors.primary)
                            .frame(width: 24)
                        Text("Privacy Policy")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)

            // Acceptance Checkbox
            Button(action: {
                hasAccepted.toggle()
            }) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasAccepted ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundColor(hasAccepted ? .blue : .secondary)

                    Text("I have read and agree to the Terms of Service and Privacy Policy")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                HStack {
                    Text("Complete Setup")
                        .fontWeight(.semibold)
                    Image(systemName: "checkmark.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasAccepted ? BrandColors.primary : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!hasAccepted)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
    }
}

#Preview {
    TermsAcceptanceView(
        hasAccepted: .constant(false),
        onContinue: {},
        onBack: {}
    )
}
