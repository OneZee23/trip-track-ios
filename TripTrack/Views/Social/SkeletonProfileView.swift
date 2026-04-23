import SwiftUI

/// Shimmer-animated placeholder that matches `PublicProfileView`'s sections
/// (hero, stats grid, active vehicle, achievements row, follow counters,
/// recent trips). Shown while the profile fetch is in flight so the user
/// sees structured ghosts instead of a blank screen or a jarring
/// content pop-in.
struct SkeletonProfileView: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        VStack(spacing: 16) {
            hero(c).padding(.top, 16)
            statsGrid(c).padding(.horizontal, 16)
            activeVehicle(c).padding(.horizontal, 16)
            achievements(c).padding(.horizontal, 16)
            followCounters(c).padding(.horizontal, 16)
            recentTrips(c).padding(.horizontal, 16)
        }
        .shimmer()
    }

    private func hero(_ c: AppTheme.Colors) -> some View {
        let avatarSize: CGFloat = 100
        let bannerHeight: CGFloat = 140
        let avatarOverlap = avatarSize / 2
        return VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 18)
                .fill(c.cardAlt)
                .frame(height: bannerHeight)

            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(c.cardAlt)
                    .frame(width: 160, height: 22)
                RoundedRectangle(cornerRadius: 10)
                    .fill(c.cardAlt)
                    .frame(width: 110, height: 22)
            }
            .padding(.top, avatarOverlap + 14)
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
                VStack(spacing: 4) {
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

    private func activeVehicle(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(c.cardAlt).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 80, height: 11)
                RoundedRectangle(cornerRadius: 3).fill(c.cardAlt).frame(height: 6)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func achievements(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 120, height: 14)
            HStack(spacing: 14) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(spacing: 6) {
                        Circle().fill(c.cardAlt).frame(width: 48, height: 48)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(c.cardAlt).frame(width: 52, height: 9)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
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

    private func recentTrips(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 100, height: 14)
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(c.cardAlt).frame(width: 80, height: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 140, height: 13)
                        RoundedRectangle(cornerRadius: 4).fill(c.cardAlt).frame(width: 90, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .surfaceCard(cornerRadius: 12)
            }
        }
    }
}
