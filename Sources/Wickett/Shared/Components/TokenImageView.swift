import SwiftUI

/// Display token logo with real on-chain metadata from Jupiter API
struct TokenImageView: View {
    let token: SolanaToken
    let size: CGFloat

    @State private var image: UIImage?
    @State private var isLoading = true

    init(token: SolanaToken, size: CGFloat = 40) {
        self.token = token
        self.size = size
    }

    var body: some View {
        Group {
            if let image = image {
                // Show real token logo
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(Circle())
            } else if isLoading {
                // Show loading state
                Circle()
                    .fill(Color(UIColor.systemGray5))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.secondary)
                    )
            } else {
                // Fallback to gradient circle with first letter
                ZStack {
                    LinearGradient(
                        colors: token.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(Circle())

                    Text(String(token.symbol.prefix(1)))
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        // Try bundled asset first (fastest and most reliable)
        let assetName = "Token\(token.symbol.uppercased())"
        if let bundledImage = UIImage(named: assetName) {
            image = bundledImage
            isLoading = false
            return
        }

        // Fall back to fetching from Jupiter API
        if let fetchedImage = await TokenMetadataService.shared.fetchImage(for: token) {
            image = fetchedImage
        }
        isLoading = false
    }
}

/// Token image with shimmer loading state
struct AsyncTokenImageView: View {
    let token: SolanaToken
    let size: CGFloat
    @State private var isLoading = false

    init(token: SolanaToken, size: CGFloat = 40) {
        self.token = token
        self.size = size
    }

    var body: some View {
        Group {
            if isLoading {
                Circle()
                    .fill(Color(UIColor.systemGray5))
                    .frame(width: size, height: size)
                    .shimmer()
            } else {
                TokenImageView(token: token, size: size)
            }
        }
        .task {
            // TODO: Download logo from Jupiter API or cache
            // For now, just use the TokenImageView directly
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview("Token Images") {
    ScrollView {
        VStack(spacing: 20) {
            Text("Token Image Components")
                .font(.title)
                .fontWeight(.bold)

            Text("Large (60pt)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            HStack(spacing: 16) {
                TokenImageView(token: TokenRegistry.SOL, size: 60)
                TokenImageView(token: TokenRegistry.USDC, size: 60)
                TokenImageView(token: TokenRegistry.USDT, size: 60)
                TokenImageView(token: TokenRegistry.wBTC, size: 60)
            }
            .padding(.horizontal)

            HStack(spacing: 16) {
                TokenImageView(token: TokenRegistry.wETH, size: 60)
                TokenImageView(token: TokenRegistry.JUP, size: 60)
                TokenImageView(token: TokenRegistry.RAY, size: 60)
                TokenImageView(token: TokenRegistry.BONK, size: 60)
            }
            .padding(.horizontal)

            Text("Medium (40pt)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)

            HStack(spacing: 16) {
                TokenImageView(token: TokenRegistry.SOL, size: 40)
                TokenImageView(token: TokenRegistry.USDC, size: 40)
                TokenImageView(token: TokenRegistry.USDT, size: 40)
                TokenImageView(token: TokenRegistry.wBTC, size: 40)
                TokenImageView(token: TokenRegistry.wETH, size: 40)
                TokenImageView(token: TokenRegistry.JUP, size: 40)
                TokenImageView(token: TokenRegistry.RAY, size: 40)
                TokenImageView(token: TokenRegistry.BONK, size: 40)
            }
            .padding(.horizontal)

            Text("Small (24pt)")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top)

            HStack(spacing: 12) {
                TokenImageView(token: TokenRegistry.SOL, size: 24)
                TokenImageView(token: TokenRegistry.USDC, size: 24)
                TokenImageView(token: TokenRegistry.USDT, size: 24)
                TokenImageView(token: TokenRegistry.wBTC, size: 24)
                TokenImageView(token: TokenRegistry.wETH, size: 24)
                TokenImageView(token: TokenRegistry.JUP, size: 24)
                TokenImageView(token: TokenRegistry.RAY, size: 24)
                TokenImageView(token: TokenRegistry.BONK, size: 24)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.vertical)
    }
    .background(Color(UIColor.systemBackground))
}
