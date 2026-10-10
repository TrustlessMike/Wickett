import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App Icon
            Image(systemName: "app.fill")
                .font(.system(size: 80))
                .foregroundColor(BrandColors.primary)

            // Welcome Title
            Text("Welcome to Wickett")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            // Description
            VStack(spacing: 16) {
                FeatureRow(
                    icon: "dollarsign.circle.fill",
                    title: "Universal Payments",
                    description: "Pay in any currency, receive anything you want"
                )

                FeatureRow(
                    icon: "arrow.triangle.2.circlepath.circle.fill",
                    title: "Smart Conversions",
                    description: "Get currency, crypto, stocks - whatever you prefer"
                )

                FeatureRow(
                    icon: "chart.line.uptrend.xyaxis.circle.fill",
                    title: "Finance Hub",
                    description: "All your banking and finance tools in one place"
                )
            }
            .padding(.horizontal)

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                HStack {
                    Text("Get Started")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(BrandColors.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(BrandColors.primary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    WelcomeView(onContinue: {})
}
