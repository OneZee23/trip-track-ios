import SwiftUI

/// A vehicle sprite standing on its own ground.
///
/// Every surface that shows a vehicle at tile size uses this rather than
/// dropping the sprite onto a card, because the card is the wrong ground in
/// both themes: on cream a white body is invisible, on the dark theme's card a
/// black one is. The plate is a constant light warm tone in both themes — see
/// `AppTheme.spritePlateTop` for why light, and why not navy.
///
/// The shadow under the wheels is not decoration. Without it the vehicle
/// floats in the middle of a coloured square; with it the square reads as a
/// surface the thing is parked on, which is also what stops the plate from
/// looking like a sticker pasted over the card.
struct VehicleSpritePlate: View {
    let assetName: String?
    /// Emoji stand-in for vehicles created before the sprites existed.
    var fallbackEmoji: String? = nil
    var plateSize: CGFloat = 64
    var spriteSize: CGFloat = 44
    var cornerRadius: CGFloat = 16

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
                .frame(width: plateSize, height: plateSize)

            if let assetName {
                ZStack {
                    Ellipse()
                        .fill(Color.black.opacity(0.16))
                        .frame(width: spriteSize * 0.62, height: spriteSize * 0.13)
                        .blur(radius: spriteSize * 0.05)
                        .offset(y: spriteSize * 0.30)

                    Image(assetName)
                        .resizable()
                        // After `resizable()`: that call rebuilds the Image and
                        // a hint set before it is not guaranteed to survive.
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: spriteSize, height: spriteSize)
                }
            } else if let fallbackEmoji {
                Text(fallbackEmoji)
                    .font(.system(size: spriteSize * 0.6))
            }
        }
    }
}
