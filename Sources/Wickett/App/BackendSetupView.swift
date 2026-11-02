import SwiftUI

/// Shown instead of the app when Firebase or Privy configuration is missing.
/// It makes no network calls and does not initialize either SDK.
struct BackendSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.primary.opacity(0.15), radius: 10, x: 0, y: 5)
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("Wickett")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Configure your own backend")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Text("This recovered prototype ships without backend configuration. Sign-in, wallets and payments stay disabled until you connect your own test projects.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    SetupItem(
                        title: "Firebase",
                        detail: "Add Resources/GoogleService-Info.plist (see GoogleService-Info.plist.example).",
                        isDone: AppConfiguration.hasFirebaseConfig
                    )
                    SetupItem(
                        title: "Privy",
                        detail: "Set the app and client IDs in AppConfiguration.swift and the privy- URL scheme in Info.plist.",
                        isDone: AppConfiguration.hasPrivyConfig
                    )
                }

                Text("Use isolated test projects. Review the transaction and authorization paths before running services.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
    }
}

private struct SetupItem: View {
    let title: String
    let detail: String
    let isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundColor(isDone ? BrandColors.success : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct BackendSetupView_Previews: PreviewProvider {
    static var previews: some View {
        BackendSetupView()
    }
}
