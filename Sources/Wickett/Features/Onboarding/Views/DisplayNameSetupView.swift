import SwiftUI

struct DisplayNameSetupView: View {
    @Binding var displayName: String
    let onContinue: () -> Void
    let onBack: () -> Void

    @FocusState private var isTextFieldFocused: Bool

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
            Image(systemName: "person.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(BrandColors.primary)

            // Title
            Text("What should we call you?")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Choose a display name for your account")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Display Name Input
            VStack(alignment: .leading, spacing: 8) {
                TextField("Display Name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .font(.body)
                    .focused($isTextFieldFocused)
                    .autocapitalization(.words)
                    .disableAutocorrection(true)

                if !displayName.isEmpty {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Looks good!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }

            Spacer()

            // Continue Button
            Button(action: onContinue) {
                HStack {
                    Text("Continue")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right.circle.fill")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(displayName.isEmpty ? Color.gray : BrandColors.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(displayName.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .padding()
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

#Preview {
    DisplayNameSetupView(
        displayName: .constant(""),
        onContinue: {},
        onBack: {}
    )
}
