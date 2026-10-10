import SwiftUI

struct RequestCreatedView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PaymentRequestViewModel()

    let request: PaymentRequest
    let qrCodeImage: UIImage?

    @State private var showShareSheet = false
    @State private var linkCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Success Header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Request Created!")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Share this request to receive payment")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 32)

                    // Request Details Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Amount")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(request.amount.formatted()) \(request.tokenSymbol)")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }

                            Spacer()

                            if request.isFixedAmount {
                                Text("Fixed")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            } else {
                                Text("Flexible")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.1))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Memo")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(request.memo)
                                .font(.body)
                        }

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Expires")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(request.expiresAt, style: .date)
                                    .font(.subheadline)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Status")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(request.status.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal)

                    // QR Code
                    if let qrImage = qrCodeImage {
                        VStack(spacing: 12) {
                            Text("Scan to Pay")
                                .font(.headline)

                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .padding()
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(radius: 4)

                            Text("Solana Pay QR Code")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    }

                    // Sharing Options
                    VStack(spacing: 12) {
                        // Copy Link Button
                        Button(action: {
                            UIPasteboard.general.string = request.shareableLink
                            linkCopied = true

                            // Reset after 2 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                linkCopied = false
                            }
                        }) {
                            HStack {
                                Image(systemName: linkCopied ? "checkmark.circle.fill" : "link.circle.fill")
                                    .font(.title3)
                                Text(linkCopied ? "Link Copied!" : "Copy Link")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(linkCopied ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                            .foregroundColor(linkCopied ? .green : .blue)
                            .cornerRadius(12)
                        }

                        // Share Sheet Button
                        Button(action: {
                            showShareSheet = true
                        }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up.circle.fill")
                                    .font(.title3)
                                Text("Share Request")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
            }
            .navigationTitle("Payment Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let qrImage = qrCodeImage {
                    ShareSheet(items: viewModel.getShareItems(for: request))
                } else {
                    ShareSheet(items: [request.shareableLink])
                }
            }
        }
    }
}

// Share Sheet wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    RequestCreatedView(
        request: PaymentRequest(
            id: "test123",
            requesterId: "user1",
            requesterName: "Mike",
            requesterAddress: "TestWallet123",
            amount: 0.5,
            tokenSymbol: "SOL",
            isFixedAmount: true,
            memo: "Coffee money",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(7 * 24 * 60 * 60),
            status: .pending,
            paymentCount: 0,
            lastPaidAt: nil,
            currency: nil,
            requesterPortfolio: nil
        ),
        qrCodeImage: nil
    )
}
