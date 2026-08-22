import SwiftUI

/// Figma 114:151 empty-state hero: double orange ring around the pixel-art
/// car on a soft accent disc. Shared by the Me-tab surfaces and by the Feed's
/// empty states — the latter used to draw their own `FeedIdleRing` with a
/// neutral grey outer ring and no disc, so the same hero looked like two
/// different components depending on which tab you were standing on.
/// `SignInIdleRing` (SignInPromptSheet) is still separate.
struct IdleRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accent.opacity(0.25), lineWidth: 2)
                .frame(width: 100, height: 100)
            ZStack {
                // The disc used to be accent at 15%, which is a warm pale
                // wash — and a warm orange car on a warm pale wash has almost
                // no contrast, so the sprite read as bleached. It takes the
                // sprite plate now, the same ground every other vehicle in the
                // app stands on. The accent stays as the ring around it, where
                // it separates the hero from the card instead of competing
                // with the thing inside it.
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Circle()
                    .stroke(AppTheme.accent, lineWidth: 2.5)
                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    // The asset is cropped to the car and is wider than it is
                    // tall, so the box is sized to the car's proportions —
                    // a square box spent a third of its height on nothing.
                    .scaledToFit()
                    .frame(width: 52, height: 32)
            }
            .frame(width: 82, height: 82)
        }
        .frame(width: 100, height: 100)
    }
}
