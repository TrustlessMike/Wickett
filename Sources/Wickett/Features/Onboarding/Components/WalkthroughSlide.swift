import SwiftUI

struct WalkthroughSlide: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: icon)
                .font(.system(size: 100))
                .foregroundColor(accentColor)

            // Title
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Description
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }
}

#Preview {
    WalkthroughSlide(
        icon: "dollarsign.circle.fill",
        title: "Pay Your Way",
        description: "Use any currency to pay, and we'll handle the rest",
        accentColor: .blue
    )
}
