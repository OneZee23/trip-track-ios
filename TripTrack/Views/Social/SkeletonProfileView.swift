import SwiftUI

/// Shimmer-animated placeholder that matches `PublicProfileView`'s always-
/// present sections (hero, stats grid, follow counters) so the cross-fade
/// swap stays pixel-aligned. Conditional sections (active vehicle, badges,
/// recent trips) intentionally aren't reserved here — the real view
/// renders them only when data is available, and pre-allocating slots
/// for them caused the skeleton→content swap to visibly shift / overlap
/// when the real profile turned out to be taller or shorter.
struct SkeletonProfileView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 16) {
            hero(c).padding(.top, 16)
            statsGrid(c).padding(.horizontal, 16)
            followCounters(c).padding(.horizontal, 16)
        }
        .shimmer()
    }

    private func hero(_ c: AppTheme.Colors) -> some View {
        let avatarSize: CGFloat = 100
        let bannerHeight: CGFloat = 140
        let avatarOverlap = avatarSize / 2
        return VStack(spacing: 0) {
            Rectangle()
                .fill(c.cardAlt)
                .frame(height: bannerHeight)

            // Mirrors the real hero: name line (22pt heavy) + rank/level pill
            // underneath, spaced by 6pt, with the same top/bottom padding so
            // the card's total height matches regardless of which branch is
            // on screen.
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(c.cardAlt)
                    .frame(width: 160, height: 22)
                RoundedRectangle(cornerRadius: 10)
                    .fill(c.cardAlt)
                    .frame(width: 110, height: 22)
            }
            .padding(.top, avatarOverlap + 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(c.card)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .top) {
            Circle()
                .fill(c.cardAlt)
                .frame(width: avatarSize, height: avatarSize)
                .overlay(Circle().stroke(c.card, lineWidth: 5))
                .padding(.top, bannerHeight - avatarOverlap)
        }
    }

    private func statsGrid(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { _ in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(c.cardAlt).frame(width: 36, height: 16)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(c.cardAlt).frame(width: 48, height: 10)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
    }

    private func followCounters(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 28, height: 17)
                    RoundedRectangle(cornerRadius: 3).fill(c.cardAlt).frame(width: 56, height: 10)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .surfaceCard(cornerRadius: 14)
    }
}
