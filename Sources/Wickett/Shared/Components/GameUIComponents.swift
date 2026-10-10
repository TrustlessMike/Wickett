import SwiftUI

// MARK: - XP Badge
struct XPBadge: View {
    let points: Int

    var body: some View {
        Text("+\(points) XP")
            .font(.system(size: 12, weight: .heavy))
            .foregroundColor(Color(red: 0.1, green: 0.3, blue: 0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.4, green: 0.8, blue: 1.0), Color(red: 0.2, green: 0.6, blue: 0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(8)
            .shadow(color: Color.blue.opacity(0.3), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Game Card Modifier
struct GameCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color.white)
            .cornerRadius(20)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 10, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.5), lineWidth: 1)
            )
    }
}

extension View {
    func gameCardStyle(padding: CGFloat = 16) -> some View {
        modifier(GameCardModifier(padding: padding))
    }
}

// MARK: - Game Progress Bar
struct GameProgressBar: View {
    let progress: Double
    var height: CGFloat = 12
    var showLabel: Bool = false
    var label: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            if let label = label {
                HStack {
                    Spacer()
                    Text(label)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(Color(red: 0.1, green: 0.1, blue: 0.2).opacity(0.8))

                    // Fill
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.8, blue: 0.2), Color(red: 1.0, green: 0.6, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * progress))
                        .shadow(color: Color.orange.opacity(0.5), radius: 4, x: 0, y: 0)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Game Slider
struct GameSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track Background
                Capsule()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.2))
                    .frame(height: 12)

                // Active Track
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.6, blue: 1.0), Color(red: 0.0, green: 0.4, blue: 0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(12, geo.size.width * percentage), height: 12)

                // Thumb (Circle)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color.white.opacity(0.9)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color(red: 0.2, green: 0.6, blue: 1.0), lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                    .offset(x: max(0, min(geo.size.width - 24, geo.size.width * percentage - 12)))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let x = value.location.x
                                let percent = max(0, min(1, x / geo.size.width))
                                let rawValue = range.lowerBound + (range.upperBound - range.lowerBound) * percent
                                let steppedValue = round(rawValue / step) * step
                                self.value = max(range.lowerBound, min(range.upperBound, steppedValue))
                            }
                    )
            }
            .frame(height: 32) // Container height to fit thumb
        }
        .frame(height: 32)
    }

    private var percentage: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}
