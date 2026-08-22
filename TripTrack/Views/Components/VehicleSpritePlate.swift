import SwiftUI

/// A vehicle sprite on the dark ground it needs, sized to the vehicle rather
/// than to its canvas.
///
/// Two facts about the art drive everything here. The sprites need brand navy
/// under them — a white body on the light theme's cream is invisible, and navy
/// is the one ground all nine colours hold on. And the whole set is cropped to
/// ONE box so a van stays taller than a hatchback, which means every shorter
/// silhouette carries empty air above it: 28% of the image height for a saloon
/// against 1% for a crossover.
///
/// So the caller gives a WIDTH and the plate works out the rest. It hangs the
/// empty part of the image above itself, where nothing can see it, and hugs
/// the vehicle. Callers that pick their own height get a plate with a hole in
/// it or a car spilling over the name, both of which this screen has been.
struct VehicleSpritePlate: View {
    let assetName: String?
    /// Emoji stand-in for vehicles created before the sprites existed.
    var fallbackEmoji: String? = nil
    /// The plate's width. Height follows the vehicle.
    var plateSize: CGFloat = 64
    /// How much of the width the vehicle takes.
    var fill: CGFloat = 0.86
    /// Pin the height to the tallest silhouette instead of to this one.
    ///
    /// On for anything in a list. A plate sized to its own vehicle is right
    /// for a hero — a crossover deserves a taller frame than a saloon — and
    /// wrong for a garage, where it makes the rows step up and down.
    var uniformHeight: Bool = false
    var cornerRadius: CGFloat = 16

    private var style: String { assetName.map(VehicleAvatar.style(ofAsset:)) ?? VehicleAvatar.defaultStyle }
    private var spriteWidth: CGFloat { plateSize * fill }
    private var spriteHeight: CGFloat { spriteWidth * CGFloat(VehicleSpriteMetrics.canvasAspect) }
    /// The drawn vehicle's own height, which is what the plate is built around.
    private var inkHeight: CGFloat { spriteHeight * CGFloat(VehicleSpriteMetrics.inkHeight(style: style)) }
    /// Room above and below the vehicle, proportional so a bicycle in a 44 pt
    /// row gets the same visual margin as a van on a 260 pt hero.
    private var plateHeight: CGFloat {
        let ink = uniformHeight
            ? spriteHeight * CGFloat(VehicleSpriteMetrics.tallestInk)
            : inkHeight
        return ink + plateSize * 0.20
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if let assetName {
                ZStack {
                    // A shadow on the ground rather than under a floating
                    // object — it is what makes the vehicle read as standing.
                    Ellipse()
                        .fill(Color.black.opacity(0.24))
                        .frame(width: inkHeight * 1.25, height: inkHeight * 0.14)
                        .blur(radius: inkHeight * 0.06)
                        .offset(y: inkHeight * 0.44)

                    Image(assetName)
                        .resizable()
                        // After `resizable()`: that call rebuilds the Image and
                        // a hint set before it is not guaranteed to survive.
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: spriteWidth, height: spriteHeight)
                        // Lifts the image so the VEHICLE lands on the plate's
                        // centre. Without it the shorter silhouettes sit on the
                        // bottom edge with a hole above them.
                        .offset(y: -CGFloat(VehicleSpriteMetrics.centeringOffset(style: style)) * spriteHeight)
                }
                // The image is taller than the plate by exactly the empty part;
                // clipping keeps that from pushing the layout around.
                .frame(width: plateSize, height: plateHeight)
                .clipped()
            } else if let fallbackEmoji {
                Text(fallbackEmoji)
                    .font(.system(size: plateSize * 0.42))
            }
        }
        .frame(width: plateSize, height: plateHeight)
    }
}
