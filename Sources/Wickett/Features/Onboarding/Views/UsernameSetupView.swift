import SwiftUI

struct UsernameSetupView: View {
    let onContinue: (String?) -> Void
    let onSkip: () -> Void

    @StateObject private var usernameService = UsernameService.shared
    @State private var username: String = ""
    @State private var isChecking: Bool = false
    @State private var isAvailable: Bool? = nil
    @State private var errorMessage: String? = nil
    @State private var checkTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "at.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(BrandColors.primary)

                Text("Choose Your Username")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Create a unique @handle so friends can easily find and pay you")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Username Input
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // @ prefix indicator
                    Text("@")
                        .font(.title2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 16)

                    // Username field
                    TextField("username", text: $username)
                        .font(.title2)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onChange(of: username) { newValue in
                            // Cancel previous check
                            checkTask?.cancel()

                            // Reset state
                            isAvailable = nil
                            errorMessage = nil

                            // Start new check with debounce
                            if !newValue.isEmpty {
                                checkTask = Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
                                    if !Task.isCancelled {
                                        await checkUsername(newValue)
                                    }
                                }
                            }
                        }

                    // Status indicator
                    if isChecking {
                        ProgressView()
                            .padding(.trailing, 16)
                    } else if let available = isAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(available ? .green : .red)
                            .font(.title3)
                            .padding(.trailing, 16)
                    }
                }
                .padding(.vertical, 16)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)

                // Error or info message
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                } else if isAvailable == true {
                    Text("@\(usernameService.normalizeUsername(username)) is available!")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                } else if username.isEmpty {
                    Text("3-20 characters • letters, numbers, hyphens, underscores")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
            }

            Spacer()

            // Action Buttons
            VStack(spacing: 12) {
                // Continue Button
                Button(action: {
                    let normalizedUsername = usernameService.normalizeUsername(username)
                    onContinue(normalizedUsername)
                }) {
                    HStack {
                        Text("Continue")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canContinue ? BrandColors.primary : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!canContinue)

                // Skip Button
                Button(action: onSkip) {
                    Text("Skip for now")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 20)
        }
        .padding()
    }

    // MARK: - Helpers

    private var canContinue: Bool {
        !username.isEmpty && isAvailable == true && !isChecking
    }

    private func checkUsername(_ value: String) async {
        await MainActor.run {
            isChecking = true
            errorMessage = nil
        }

        do {
            let result = try await usernameService.checkAvailability(username: value)

            await MainActor.run {
                isChecking = false
                isAvailable = result.available
                if !result.available {
                    errorMessage = result.reason
                }
            }
        } catch {
            await MainActor.run {
                isChecking = false
                isAvailable = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    UsernameSetupView(
        onContinue: { _ in },
        onSkip: { }
    )
}
