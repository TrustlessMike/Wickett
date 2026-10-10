import SwiftUI

struct PortfolioAllocationView: View {
    @Binding var portfolio: [PortfolioAllocation]
    let onSave: ([PortfolioAllocation]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editablePortfolio: [PortfolioAllocation] = []
    @State private var validationError: String?
    @State private var showPresetConfirmation = false
    @State private var selectedPreset: PortfolioPreset?
    @State private var viewMode: ViewMode = .selection

    enum ViewMode {
        case selection
        case suggestedPreview
        case editor
    }

    enum PortfolioPreset: CaseIterable {
        case crypto
        case diversified

        var name: String {
            switch self {
            case .crypto: return "Crypto Only"
            case .diversified: return "Gold & Stocks"
            }
        }

        var description: String {
            switch self {
            case .crypto: return "Exposure to top crypto assets on Solana."
            case .diversified: return "Balanced mix of crypto, gold, and tech stocks."
            }
        }

        var icon: String {
            switch self {
            case .crypto: return "bitcoinsign.circle.fill"
            case .diversified: return "chart.pie.fill"
            }
        }

        var allocations: [PortfolioAllocation] {
            switch self {
            case .crypto:
                return [
                    PortfolioAllocation(token: SupportedToken.sol.mint, symbol: "SOL", percentage: 50),
                    PortfolioAllocation(token: SupportedToken.usdc.mint, symbol: "USDC", percentage: 30),
                    PortfolioAllocation(token: SupportedToken.bonk.mint, symbol: "BONK", percentage: 20)
                ]
            case .diversified:
                return [
                    PortfolioAllocation(token: SupportedToken.sol.mint, symbol: "SOL", percentage: 40),
                    PortfolioAllocation(token: SupportedToken.gold.mint, symbol: "GOLD", percentage: 20),
                    PortfolioAllocation(token: SupportedToken.aapl.mint, symbol: "AAPL", percentage: 20),
                    PortfolioAllocation(token: SupportedToken.tsla.mint, symbol: "TSLA", percentage: 20)
                ]
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                switch viewMode {
                case .selection:
                    StrategySelectionView(
                        onSelectSuggested: { viewMode = .suggestedPreview },
                        onSelectManual: {
                            editablePortfolio = []
                            viewMode = .editor
                        }
                    )
                    .transition(.move(edge: .leading))

                case .suggestedPreview:
                    PresetSelectionView(
                        onSelect: { preset in
                            applyPreset(preset)
                            viewMode = .editor
                        },
                        onBack: { viewMode = .selection }
                    )
                    .transition(.move(edge: .trailing))

                case .editor:
                    editorView
                        .transition(.opacity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                if viewMode == .editor {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Reset") {
                            withAnimation {
                                editablePortfolio = []
                                viewMode = .selection
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .animation(.easeInOut, value: viewMode)
            .onAppear {
                if !portfolio.isEmpty {
                    editablePortfolio = portfolio
                    viewMode = .editor
                }
            }
        }
    }

    // MARK: - Subviews for Flows

    struct StrategySelectionView: View {
        @Environment(\.colorScheme) var colorScheme
        let onSelectSuggested: () -> Void
        let onSelectManual: () -> Void

        var body: some View {
            VStack(spacing: 24) {
                Spacer()

                Text("Setup Your Portfolio")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text("Choose how you want to allocate your incoming payments.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 16) {
                    Button(action: onSelectSuggested) {
                        HStack(spacing: 16) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.yellow)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Suggested Strategies")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Pick from expert-curated sets")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(20)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
                    }

                    Button(action: onSelectManual) {
                        HStack(spacing: 16) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 32))
                                .foregroundColor(BrandColors.primary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build Your Own")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Select individual tokens manually")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                        }
                        .padding(20)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
        }
    }

    struct PresetSelectionView: View {
        @Environment(\.colorScheme) var colorScheme
        let onSelect: (PortfolioPreset) -> Void
        let onBack: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    Spacer()
                }
                .padding()

                ScrollView {
                    VStack(spacing: 24) {
                        Text("Choose a Strategy")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .padding(.top)

                        ForEach(PortfolioPreset.allCases, id: \.self) { preset in
                            Button(action: { onSelect(preset) }) {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Image(systemName: preset.icon)
                                            .font(.title)
                                            .foregroundColor(BrandColors.primary)
                                        Text(preset.name)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.primary)
                                        Spacer()
                                    }

                                    Text(preset.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)

                                    // Mini allocation preview
                                    HStack(spacing: 8) {
                                        ForEach(preset.allocations.prefix(4)) { item in
                                            Text("\(item.symbol) \(Int(item.percentage))%")
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.gray.opacity(0.2))
                                                .cornerRadius(6)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(20)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .cornerRadius(20)
                                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    // MARK: - Editor View (Main Logic)

    private var editorView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    // Visual Ring Chart
                    ZStack {
                        if editablePortfolio.isEmpty {
                            Circle()
                                .stroke(Color.secondary.opacity(0.1), lineWidth: 24)
                                .frame(width: 220, height: 220)
                            Text("Empty")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        } else {
                            PortfolioRingChart(portfolio: editablePortfolio)
                                .frame(width: 220, height: 220)

                            VStack(spacing: 4) {
                                Text("\(Int(totalPercentage))%")
                                    .font(.system(size: 48, weight: .heavy))
                                    .foregroundColor(isValidTotal ? .primary : .red)
                                Text("Allocated")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 40)

                    // List of Allocations
                    VStack(spacing: 20) {
                        ForEach($editablePortfolio) { $allocation in
                            AllocationRow(allocation: $allocation, onDelete: {
                                removeToken(allocation)
                            })
                        }

                        // Clean "Add Token" Menu (No suggestions here anymore)
                        Menu {
                            ForEach(SupportedToken.allCases, id: \.self) { token in
                                if !editablePortfolio.contains(where: { $0.symbol == token.rawValue.uppercased() }) {
                                    Button(action: { addToken(token) }) {
                                        HStack {
                                            Text(token.rawValue.uppercased())
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Add Token")
                                    .fontWeight(.bold)
                            }
                            .font(.headline)
                            .foregroundColor(BrandColors.primary)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(BrandColors.primary.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 100)
                }
            }

            // Sticky Footer
            VStack(spacing: 16) {
                if let error = validationError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                Button(action: handleSave) {
                    Text("Save Portfolio")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValidTotal ? BrandColors.primary : Color.gray)
                        .cornerRadius(20)
                        .shadow(color: (isValidTotal ? BrandColors.primary : Color.gray).opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .disabled(!isValidTotal)
            }
            .padding(20)
            .background(Color(UIColor.systemBackground))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: -4)
        }
        .navigationTitle("Edit Portfolio")
    }

    // MARK: - Helpers

    private var totalPercentage: Double {
        editablePortfolio.reduce(0) { $0 + $1.percentage }
    }

    private var isValidTotal: Bool {
        abs(totalPercentage - 100.0) < 0.01
    }

    private func applyPreset(_ preset: PortfolioPreset) {
        editablePortfolio = preset.allocations
    }

    private func addToken(_ token: SupportedToken) {
        let newAllocation = PortfolioAllocation(
            token: token.mint,
            symbol: token.rawValue.uppercased(),
            percentage: 0
        )
        editablePortfolio.append(newAllocation)
    }

    private func removeToken(_ allocation: PortfolioAllocation) {
        editablePortfolio.removeAll { $0.id == allocation.id }
    }

    private func handleSave() {
        let validation = DelegationManager.shared.validatePortfolio(editablePortfolio)
        if validation.isValid {
            validationError = nil
            onSave(editablePortfolio)
        } else {
            validationError = validation.error
        }
    }
}

// MARK: - Subviews (AllocationRow & RingChart reused from before)

struct AllocationRow: View {
    @Environment(\.colorScheme) var colorScheme
    @Binding var allocation: PortfolioAllocation
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                // Token Label
                HStack(spacing: 12) {
                    tokenImage(for: allocation.symbol)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

                    Text(allocation.symbol)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Percentage Display
                Text("\(Int(allocation.percentage))%")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(BrandColors.primary)

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(.red.opacity(0.6))
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
                .padding(.leading, 8)
            }

            // Custom Slider
            VStack(spacing: 8) {
                GameSlider(value: $allocation.percentage, range: 0...100, step: 5)
                    .frame(height: 32)

                HStack {
                    Text("0%")
                    Spacer()
                    Text("100%")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .padding(20)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
    }
}

struct PortfolioRingChart: View {
    let portfolio: [PortfolioAllocation]

    var body: some View {
        Canvas { context, size in
            let total = portfolio.reduce(0) { $0 + $1.percentage }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 24
            let strokeWidth: CGFloat = 24

            // Draw background ring
            let backgroundPath = Path { p in
                p.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            }
            context.stroke(backgroundPath, with: .color(Color.gray.opacity(0.1)), lineWidth: strokeWidth)

            var startAngle = Angle.degrees(-90)

            for (index, item) in portfolio.enumerated() {
                let angle = Angle.degrees(360 * (item.percentage / 100))
                let endAngle = startAngle + angle

                let path = Path { p in
                    p.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                }

                context.stroke(
                    path,
                    with: .color(color(for: index)),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

                startAngle = endAngle
            }
        }
    }

    func color(for index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.2, green: 0.8, blue: 0.4), // Green
            Color(red: 0.2, green: 0.6, blue: 1.0), // Blue
            Color(red: 0.8, green: 0.2, blue: 0.8), // Purple
            Color(red: 1.0, green: 0.6, blue: 0.0), // Orange
            Color(red: 1.0, green: 0.2, blue: 0.4), // Pink
            Color(red: 0.2, green: 0.8, blue: 1.0)  // Cyan
        ]
        return colors[index % colors.count]
    }
}

// MARK: - Asset Helper

private func tokenImage(for symbol: String) -> some View {
    Group {
        if let image = loadAssetImage(for: symbol) {
            image
                .resizable()
        } else {
            // Fallback
            ZStack {
                Circle().fill(BrandColors.primary.opacity(0.2))
                Text(symbol.prefix(1)).font(.caption).bold()
            }
        }
    }
}

private func loadAssetImage(for symbol: String) -> Image? {
    switch symbol.uppercased() {
    case "SOL": return Image("TokenSOL")
    case "USDC": return Image("TokenUSDC")
    case "BONK": return Image("TokenBONK")
    case "JUP": return Image("TokenJUP")
    case "WETH": return Image("TokenWETH")
    case "WBTC": return Image("TokenWBTC")
    case "GOLD": return Image("TokenGOLD")
    case "AAPL": return Image("TokenAAPLX")
    case "TSLA": return Image("TokenTSLAX")
    case "NVDA": return Image("TokenNVDAX")
    case "MSFT": return Image("TokenMSFTX")
    case "AMZN": return Image("TokenAMZNX")
    default: return nil
    }
}

#Preview {
    PortfolioAllocationView(portfolio: .constant([]), onSave: { _ in })
}
