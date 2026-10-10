import SwiftUI

struct LoginView: View {
    let onAppleSignIn: () async -> Void
    let onGoogleSignIn: () async -> Void

    var body: some View {
        VStack(spacing: 30) {
            // App Logo
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 27))
                .shadow(color: Color.primary.opacity(0.15), radius: 10, x: 0, y: 5)
                .padding(.top, 50)

            // App Name
            Text("Wickett")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            // Sign in section
            VStack(spacing: 20) {
                Text("Sign in to continue")
                    .font(.headline)
                    .foregroundColor(.secondary)

                // Apple Sign In Button
                SignInButton(
                    icon: "applelogo",
                    title: "Sign in with Apple",
                    backgroundColor: .black,
                    action: onAppleSignIn
                )

                // Google Sign In Button
                SignInButton(
                    icon: "g.circle.fill",
                    title: "Sign in with Google",
                    backgroundColor: Color(red: 0.26, green: 0.52, blue: 0.96),
                    action: onGoogleSignIn
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

// MARK: - Sign In Button Component
private struct SignInButton: View {
    let icon: String
    let title: String
    let backgroundColor: Color
    let action: () async -> Void

    var body: some View {
        Button(action: {
            Task {
                await action()
            }
        }) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(8)
        }
    }
}
