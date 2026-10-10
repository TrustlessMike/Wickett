import SwiftUI

struct ConfettiView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<50) { i in
                ConfettiParticle(animate: $animate, index: i)
            }
        }
        .onAppear {
            animate = true
        }
    }
}

struct ConfettiParticle: View {
    @Binding var animate: Bool
    let index: Int

    // Random properties for each particle
    @State private var xOffset: CGFloat = 0
    @State private var yOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1

    // Random configuration
    let color: Color = [
        BrandColors.primary,
        BrandColors.cyan,
        .purple,
        .yellow,
        .green,
        .pink
    ].randomElement()!

    let shape: ParticleShape = [.circle, .rectangle, .capsule].randomElement()!

    enum ParticleShape {
        case circle, rectangle, capsule
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch shape {
                case .circle:
                    Circle()
                        .fill(color)
                case .rectangle:
                    Rectangle()
                        .fill(color)
                case .capsule:
                    Capsule()
                        .fill(color)
                }
            }
            .frame(width: 8, height: 8)
            .scaleEffect(scale)
            .rotationEffect(Angle(degrees: rotation))
            .offset(x: xOffset, y: yOffset)
            .opacity(animate ? 0 : 1) // Fade out at end
            .position(x: geo.size.width / 2, y: geo.size.height / 2) // Start from center
            .onAppear {
                if animate {
                    runAnimation(in: geo.size)
                }
            }
            .onChange(of: animate) { _ in
                if animate {
                    runAnimation(in: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func runAnimation(in size: CGSize) {
        // Random ending position (explode outwards)
        let randomAngle = Double.random(in: 0...360) * .pi / 180
        let randomDistance = Double.random(in: 100...400)

        let endX = CGFloat(cos(randomAngle) * randomDistance)
        let endY = CGFloat(sin(randomAngle) * randomDistance) - 100 // Bias upwards slightly like a pop

        // Animation timing
        let duration = Double.random(in: 1.5...2.5)
        let delay = Double.random(in: 0...0.2)

        withAnimation(.easeOut(duration: duration).delay(delay)) {
            xOffset = endX
            yOffset = endY + 500 // Gravity effect (fall down at end)
            rotation = Double.random(in: 360...1440) // Spin wildly
            scale = 0 // Shrink to nothing
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ConfettiView()
    }
}
