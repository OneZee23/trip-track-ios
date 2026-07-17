import SwiftUI

/// Figma 114:151 empty-state hero: double orange ring around the pixel-art
/// car on a soft accent disc. Shared component for the Me-tab surfaces; the
/// existing `FeedIdleRing` (FeedView) and `SignInIdleRing` (SignInPromptSheet)
/// stay untouched — triplication flagged for a later cleanup pass.
struct IdleRing: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(AppTheme.accent.opacity(0.25), lineWidth: 2)
                .frame(width: 100, height: 100)
            ZStack {
                Circle()
                    .fill(AppTheme.accentBg)
                Circle()
                    .stroke(AppTheme.accent, lineWidth: 2)
                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    // The sprite asset is non-square — without fit it
                    // squeezes into the 46×46 box.
                    .scaledToFit()
                    .frame(width: 46, height: 46)
            }
            .frame(width: 82, height: 82)
        }
        .frame(width: 100, height: 100)
    }
}
