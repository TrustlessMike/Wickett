import SwiftUI

struct RequestListView: View {
    @StateObject private var viewModel = PaymentRequestViewModel()
    @State private var showCreateRequest = false

    let user: User

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingMyRequests {
                    ProgressView("Loading requests...")
                } else if viewModel.myRequests.isEmpty {
                    emptyStateView
                } else {
                    requestsList
                }
            }
            .navigationTitle("My Requests")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showCreateRequest = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .refreshable {
                await viewModel.loadMyRequests()
            }
            .task {
                await viewModel.loadMyRequests()
            }
            .sheet(isPresented: $showCreateRequest) {
                CreateRequestView(user: user)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Requests Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a payment request to get started")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {
                showCreateRequest = true
            }) {
                Text("Create Request")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var requestsList: some View {
        List {
            ForEach(viewModel.myRequests) { request in
                RequestRowView(request: request)
            }
        }
        .listStyle(.plain)
    }
}

struct RequestRowView: View {
    let request: PaymentRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(request.amount.formatted()) \(request.tokenSymbol)")
                    .font(.headline)

                Spacer()

                statusBadge
            }

            Text(request.memo)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                Label(
                    "Payments: \(request.paymentCount)",
                    systemImage: "checkmark.circle"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                if request.isExpired {
                    Text("Expired")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Expires \(request.expiresAt, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var statusBadge: some View {
        Text(request.status.displayName)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch request.status {
        case .pending:
            return .blue
        case .paid:
            return .green
        case .expired:
            return .red
        case .rejected:
            return .orange
        }
    }
}

#Preview {
    RequestListView(user: User(
        id: "test",
        email: "test@example.com",
        name: "Test User",
        walletAddress: "TestWallet123", username: nil
    ))
}
