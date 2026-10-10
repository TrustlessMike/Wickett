import SwiftUI

/// Shimmer effect modifier for skeleton loading states
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.3),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: phase * geometry.size.width)
                        .mask(content)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    /// Apply shimmer loading effect to any view
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}

/// Generic skeleton loading view
struct SkeletonView: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    init(width: CGFloat? = nil, height: CGFloat = 20, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(UIColor.systemGray5))
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// Skeleton for balance card
struct SkeletonBalanceCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Total Balance" label skeleton
            SkeletonView(width: 120, height: 16, cornerRadius: 4)

            // Large balance amount skeleton
            SkeletonView(width: 200, height: 40, cornerRadius: 8)

            // "Today" change skeleton
            SkeletonView(width: 100, height: 14, cornerRadius: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
    }
}

/// Skeleton for individual token row
struct SkeletonTokenRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Token icon skeleton
            Circle()
                .fill(Color(UIColor.systemGray5))
                .frame(width: 40, height: 40)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                // Token name skeleton
                SkeletonView(width: 80, height: 16, cornerRadius: 4)

                // Token amount skeleton
                SkeletonView(width: 120, height: 14, cornerRadius: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                // USD value skeleton
                SkeletonView(width: 100, height: 16, cornerRadius: 4)

                // 24h change skeleton
                SkeletonView(width: 60, height: 14, cornerRadius: 4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// Skeleton for token list (multiple rows)
struct SkeletonTokenList: View {
    let count: Int

    init(count: Int = 3) {
        self.count = count
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonTokenRow()
            }
        }
    }
}

/// Skeleton for quote card (swap rates, price impact, etc)
struct SkeletonQuoteCard: View {
    var body: some View {
        VStack(spacing: 16) {
            // Exchange Rate row
            HStack {
                SkeletonView(width: 80, height: 14, cornerRadius: 4)
                Spacer()
                SkeletonView(width: 150, height: 14, cornerRadius: 4)
            }

            Divider()

            // Price Impact row
            HStack {
                SkeletonView(width: 100, height: 14, cornerRadius: 4)
                Spacer()
                SkeletonView(width: 60, height: 14, cornerRadius: 4)
            }

            Divider()

            // Minimum Received row
            HStack {
                SkeletonView(width: 120, height: 14, cornerRadius: 4)
                Spacer()
                SkeletonView(width: 100, height: 14, cornerRadius: 4)
            }

            Divider()

            // Slippage Tolerance row
            HStack {
                SkeletonView(width: 130, height: 14, cornerRadius: 4)
                Spacer()
                SkeletonView(width: 50, height: 14, cornerRadius: 4)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// Skeleton for transaction row (activity feed)
struct SkeletonTransactionRow: View {
    var body: some View {
        HStack(spacing: 12) {
            // Transaction type icon skeleton
            Circle()
                .fill(Color(UIColor.systemGray5))
                .frame(width: 40, height: 40)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                // Transaction description skeleton
                SkeletonView(width: 120, height: 16, cornerRadius: 4)

                // Transaction date skeleton
                SkeletonView(width: 80, height: 14, cornerRadius: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                // Amount skeleton
                SkeletonView(width: 90, height: 16, cornerRadius: 4)

                // USD value skeleton
                SkeletonView(width: 60, height: 14, cornerRadius: 4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

/// Skeleton for transaction list (multiple rows)
struct SkeletonTransactionList: View {
    let count: Int

    init(count: Int = 5) {
        self.count = count
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonTransactionRow()
            }
        }
    }
}

// MARK: - Preview

#Preview("Skeleton Components") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Skeleton Loading States")
                .font(.title)
                .fontWeight(.bold)

            Text("Balance Card")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            SkeletonBalanceCard()
                .padding(.horizontal)

            Text("Token List")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            SkeletonTokenList(count: 5)
                .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .background(Color(UIColor.systemBackground))
}
