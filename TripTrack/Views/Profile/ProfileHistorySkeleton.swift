import SwiftUI

/// Placeholder cards for История while the library is still being read.
///
/// The Я screen used to draw its header and stats and then simply stop: the
/// whole Достижения + История block is gated on having trips, and "no trips
/// yet" and "not read yet" looked identical. On a big library that is a
/// visible second of a screen that appears to have ended, and the cards then
/// arrive as a jolt that shoves «Со мной» down the page.
///
/// This holds that space with the shape of what is coming — same card
/// geometry, same margins — so the arrival is a fill rather than a jump.
/// Deliberately dumb: no shimmer sweep, no spinner. A pulse is enough to say
/// «working», and anything livelier competes with the content it stands in for.
struct ProfileHistorySkeleton: View {
    /// Matches whichever layout История is set to, or the wait is followed by
    /// a second re-layout when the real cards land in the other shape.
    let isGrid: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var dim = false

    /// Two rows of tiles, three cards — about a screenful either way, and
    /// past that the user is scrolling into content that has landed.
    private static let cardCount = 3
    private static let tileCount = 4

    /// `ProfileTripCardView`'s map is 178 plus its header and footer rows.
    private static let cardHeight: CGFloat = 268
    /// `ProfileTripTile`'s thumbnail plus its two lines of text.
    private static let tileHeight: CGFloat = 148

    private static let gridColumns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 2
    )

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        Group {
            if isGrid {
                LazyVGrid(columns: Self.gridColumns, spacing: 8) {
                    ForEach(0..<Self.tileCount, id: \.self) { _ in
                        block(c, height: Self.tileHeight, radius: 14)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(0..<Self.cardCount, id: \.self) { _ in
                        block(c, height: Self.cardHeight, radius: 16)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .opacity(dim ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
        .onAppear { dim = true }
        // One element, one sentence: VoiceOver must not walk three identical
        // empty rectangles.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.loadingTrips(LanguageManager.currentLanguage))
        .accessibilityIdentifier("profile_history_skeleton")
    }

    private func block(_ c: AppTheme.Colors, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(c.cardAlt)
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}
