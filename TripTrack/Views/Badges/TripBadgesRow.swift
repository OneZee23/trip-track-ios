import SwiftUI

struct TripBadgesRow: View {
    let badgeIds: [String]
    var maxVisible: Int = 4
    var size: CGFloat = 28
    var showCounts: Bool = false
    var earnCounts: [String: Int] = [:]
    var onTap: ((Badge) -> Void)?

    @Environment(\.colorScheme) private var scheme

    private static let badgeLookup: [String: Badge] = {
        Dictionary(uniqueKeysWithValues: Badge.all.map { ($0.id, $0) })
    }()

    private var visibleBadges: [Badge] {
        let matched = badgeIds.compactMap { Self.badgeLookup[$0] }
        return Array(matched.prefix(maxVisible))
    }

    private var overflowCount: Int {
        max(0, badgeIds.count - maxVisible)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        HStack(spacing: size * 0.2) {
            ForEach(visibleBadges) { badge in
                badgeIcon(badge, count: earnCounts[badge.id] ?? 1, c: c)
                    .onTapGesture {
                        onTap?(badge)
                    }
            }

            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: size, height: size)
                    .background(c.textSecondary.opacity(0.1), in: Circle())
            }
        }
    }

    private func badgeIcon(_ badge: Badge, count: Int, c: AppTheme.Colors) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(badge.color.opacity(0.15))
                    .frame(width: size, height: size)

                Image(systemName: badge.icon)
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(badge.color)
            }

            if showCounts && badge.isRepeatable && count > 1 {
                Text("x\(count)")
                    .font(.system(size: max(8, size * 0.28), weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(badge.color, in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
    }
}
