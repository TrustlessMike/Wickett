import SwiftUI

struct LoadingOverlay: View {
    let message: String
    let isSuccess: Bool

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Card with message
            VStack(spacing: 20) {
                if isSuccess {
                    // Success checkmark
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                } else {
                    // Loading spinner
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: BrandColors.primary))
                }

                Text(message)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(40)
        }
    }
}

#Preview {
    VStack {
        LoadingOverlay(message: "Sending $10.00 to Mike...", isSuccess: false)
    }
}

#Preview("Success") {
    VStack {
        LoadingOverlay(message: "Sent $10.00 to Mike ✓", isSuccess: true)
    }
}
