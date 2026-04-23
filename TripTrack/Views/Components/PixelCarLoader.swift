import SwiftUI

/// Pixel-car loader: the brand icon parked on a dashed road. Used as a
/// calm empty-state placeholder on social screens. Used to slide across
/// the frame — got rid of the animation because the motion kept drawing
/// the eye away from the accompanying label every time the list refetched.
struct PixelCarLoader: View {
    var label: String?
    var height: CGFloat = 120

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 14) {
            GeometryReader { geo in
                let roadY = geo.size.height * 0.7
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: roadY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: roadY))
                    }
                    .stroke(
                        c.textTertiary.opacity(0.35),
                        style: StrokeStyle(lineWidth: 2, dash: [6, 6])
                    )

                    Image("PixelCar")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: 34)
                        .position(x: geo.size.width / 2, y: roadY - 34 / 2 - 2)
                }
            }
            .frame(height: height)

            if let label {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
        }
    }
}
