import SwiftUI

struct LoadingView: View {
    let message: String
    @State private var isAnimating = false

    init(message: String = "Loading...") {
        self.message = message
    }

    var body: some View {
        VStack(spacing: 30) {
            // App Icon with pulse animation
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(BrandColors.primary.opacity(0.3), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0 : 1)

                // App Icon
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color.primary.opacity(0.15), radius: 10, x: 0, y: 5)
            }
            .onAppear {
                withAnimation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }

            // Loading spinner
            ProgressView()
                .scaleEffect(1.2)
                .tint(BrandColors.primary)

            // Message
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
