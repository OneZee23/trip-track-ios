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
                        // Was 0.35 and read as a hairline the car floated over.
                        // The road is the other half of this picture.
                        c.textTertiary.opacity(0.55),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [9, 8])
                    )

                    // The sprite used to be a square canvas whose car filled
                    // just over half the height, so a 34 pt frame drew an 18 pt
                    // car — small and washed out on a cream background. The
                    // asset is cropped to the car now; the frame is the car.
                    let carHeight = min(52, geo.size.height * 0.42)

                    // A shadow on the road, not under a floating object: it is
                    // what makes the car read as standing on the dashes rather
                    // than hovering over them.
                    Ellipse()
                        .fill(Color.black.opacity(0.14))
                        .frame(width: carHeight * 1.5, height: carHeight * 0.2)
                        .blur(radius: carHeight * 0.09)
                        .position(x: geo.size.width / 2, y: roadY)

                    Image("PixelCar")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(height: carHeight)
                        .position(x: geo.size.width / 2, y: roadY - carHeight / 2 + 2)
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
