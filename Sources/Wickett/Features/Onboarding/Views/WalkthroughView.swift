import SwiftUI

struct WalkthroughView: View {
    let onContinue: () -> Void
    let onBack: () -> Void

    @State private var currentPage = 0

    private let slides = [
        WalkthroughSlideData(
            icon: "dollarsign.circle.fill",
            title: "Pay Your Way",
            description: "Use any currency to pay. Cash, crypto, or credit - we accept it all.",
            accentColor: BrandColors.primary
        ),
        WalkthroughSlideData(
            icon: "arrow.triangle.2.circlepath.circle.fill",
            title: "Receive Anything",
            description: "Get paid in currency, crypto, stocks, or whatever you prefer. Your choice.",
            accentColor: .green
        ),
        WalkthroughSlideData(
            icon: "chart.line.uptrend.xyaxis.circle.fill",
            title: "All-in-One Finance",
            description: "Banking, payments, and investments - everything you need in one place.",
            accentColor: .purple
        )
    ]

    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                }
                Spacer()
                Button("Skip") {
                    onContinue()
                }
                .foregroundColor(BrandColors.primary)
            }
            .padding(.horizontal)

            // Slide Content
            TabView(selection: $currentPage) {
                ForEach(0..<slides.count, id: \.self) { index in
                    WalkthroughSlide(
                        icon: slides[index].icon,
                        title: slides[index].title,
                        description: slides[index].description,
                        accentColor: slides[index].accentColor
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Continue/Next Button
            Button(action: handleContinue) {
                HStack {
                    Text(currentPage == slides.count - 1 ? "Continue" : "Next")
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

    private func handleContinue() {
        if currentPage < slides.count - 1 {
            withAnimation {
                currentPage += 1
            }
        } else {
            onContinue()
        }
    }
}

// MARK: - Supporting Types

struct WalkthroughSlideData {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
}

#Preview {
    WalkthroughView(
        onContinue: {},
        onBack: {}
    )
}
