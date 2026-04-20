import SwiftUI

/// Pixel-car loader: the brand icon slides left-to-right over a dashed road.
/// Used as a playful empty-state spinner on social screens.
struct PixelCarLoader: View {
    var label: String?
    var height: CGFloat = 120

    @State private var isAnimating = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 14) {
            GeometryReader { geo in
                let roadY = geo.size.height * 0.7
                ZStack(alignment: .leading) {
                    // Dashed road line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: roadY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: roadY))
                    }
                    .stroke(
                        c.textTertiary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )

                    // Car sprite sliding left → right
                    Image("PixelCar")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: 34)
                        .offset(
                            x: isAnimating ? geo.size.width - 34 : 0,
                            y: roadY - 34 - 2
                        )
                        .animation(
                            .linear(duration: 1.6)
                                .repeatForever(autoreverses: false),
                            value: isAnimating
                        )
                }
            }
            .frame(height: height)

            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
        }
        .onAppear { isAnimating = true }
    }
}
