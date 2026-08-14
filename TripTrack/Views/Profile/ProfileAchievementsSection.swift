import SwiftUI

// MARK: - Section (Figma 909:385)

/// «Достижения» on the Я tab: a progress counter in the header, one featured
/// badge, and a strip of the next-rarest ones.
struct ProfileAchievementsSection: View {
    let trips: [Trip]
    let onTapAll: () -> Void
    let onTapBadge: (Badge) -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    /// Observed, not read statically: the pin is written by the award detail
    /// screen, and this row is what has to show «Закреплено» when you come back.
    @ObservedObject private var settings = SettingsManager.shared
    @State private var content = AchievementsContent()
    /// Zero unlocked badges and "not counted yet" are the same value in
    /// `content`, and the walk is async — without this the card flashes «Пока
    /// ничего не открыто» on every mount, including for a user with forty.
    @State private var hasLoaded = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(alignment: .leading, spacing: 0) {
            header(c)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)

            card(c)
                .padding(.horizontal, 16)
        }
        // Unlocking walks every trip and every badge predicate — once per
        // input change, never per redraw. Two things can change the answer:
        // the trip set (badges are milestone-shaped, so a title edit on an
        // existing trip cannot flip one — the COUNT is the whole identity),
        // and the pin, which is set on a screen two pushes away and has to
        // repaint this row on the way back without an app relaunch.
        .task(id: "\(trips.count)|\(settings.pinnedBadgeId)") { await load() }
    }

    // MARK: - Header

    private func header(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 8) {
            ProfileSectionLabel(text: AppStrings.achievementsSection(lang.language))

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                onTapAll()
            } label: {
                HStack(spacing: 5) {
                    // Blank, not «0 из 0», until the walk resolves.
                    Text(hasLoaded
                         ? AppStrings.achievementsProgress(
                            lang.language,
                            unlocked: content.unlockedCount,
                            total: content.totalCount)
                         : "")
                    .font(.system(size: 13, weight: .semibold))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(c.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_achievements_all")
        }
    }

    // MARK: - Card

    private func card(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 12) {
            if let featured = content.featured {
                featuredRow(featured, c)
                if !content.strip.isEmpty || content.overflow > 0 {
                    stripRow(c)
                }
            } else if hasLoaded {
                emptyState(c)
            } else {
                // Hold the card's height while the walk runs, so the section
                // doesn't pop the whole screen down when it resolves.
                Color.clear.frame(height: 30)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("profile_achievements")
    }

    /// The one badge worth reading a line about — the rest of the card is discs.
    private func featuredRow(_ badge: Badge, _ c: AppTheme.Colors) -> some View {
        let rarity = badge.displayRarity
        return Button {
            Haptics.tap()
            onTapBadge(badge)
        } label: {
            HStack(spacing: 10) {
                BadgeRarityChip(badge: badge, iconSize: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(badge.title(lang.language))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)

                    Text(featuredSubtitle(badge))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(rarity.chipText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rarity.rowTint, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    /// Equal gaps across whatever width the device gives us — canon's 300pt is
    /// a 360pt artboard measuring itself, not a size to pin the strip to.
    private func stripRow(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            ForEach(content.strip) { badge in
                Button {
                    Haptics.tap()
                    onTapBadge(badge)
                } label: {
                    BadgeRarityChip(badge: badge, iconSize: 15)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            if content.overflow > 0 {
                Button {
                    Haptics.tap()
                    onTapAll()
                } label: {
                    Text("+\(content.overflow)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textSecondary)
                        .frame(width: 34, height: 30)
                        .background(c.cardAlt, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func emptyState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 4) {
            Text(AppStrings.achievementsEmpty(lang.language))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.text)

            Text(AppStrings.achievementsEmptyHint(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Copy

    /// «Закреплено · Легендарная · 0,4%». Only the parts that are true of this
    /// badge — pinning is opt-in and the global share is backend-fed, so both
    /// are usually absent — joined so a missing part leaves no dangling « · ».
    private func featuredSubtitle(_ badge: Badge) -> String {
        let l = lang.language
        var parts: [String] = []
        if content.isFeaturedPinned { parts.append(AppStrings.achievementPinned(l)) }
        parts.append(badge.displayRarity.title(l))
        if let percent = badge.globalUnlockPercent {
            parts.append(Badge.unlockShareText(percent, l) + "%")
        }
        return parts.joined(separator: " · ")
    }


    // MARK: - Data

    private func load() async {
        // `computeStats` reads the streak row off the CoreData view context, so
        // the trip walk has to stay on the main actor; only the pure pass over
        // the badge catalogue goes off. Profile trips carry no track points
        // (see `fetchTrips(limit:offset:)`), so the walk itself is O(trips).
        let stats = BadgeManager.computeStats(from: trips)
        // One store for the pin: `SettingsManager.pinnedBadgeId` already exists
        // for exactly this row («" " = none»). A second UserDefaults key here
        // would read empty forever once the badge screen's pin action lands.
        let pinnedId = settings.pinnedBadgeId.isEmpty ? nil : settings.pinnedBadgeId
        let built = await Task.detached(priority: .userInitiated) {
            AchievementsContent.build(stats: stats, pinnedId: pinnedId)
        }.value
        guard !Task.isCancelled else { return }
        content = built
        hasLoaded = true
    }
}

// MARK: - Rarity Chip

/// The 30pt rarity disc. Shared by the featured row and the strip, which differ
/// only in glyph size.
///
/// The glyph takes the ring colour, not `badge.color`: canon specifies the chip
/// as exactly two colours, and a per-badge hue inside a per-rarity ring puts two
/// unrelated colour systems in one 30pt circle (green glyph, purple ring).
private struct BadgeRarityChip: View {
    let badge: Badge
    var iconSize: CGFloat = 15

    var body: some View {
        let rarity = badge.displayRarity
        ZStack {
            Circle().fill(rarity.chipTint)
            Circle().strokeBorder(rarity.chipRing, lineWidth: 1.5)
            // Ink, not the ring: the glyph is a filled shape on a tint of its
            // own hue, where the undarkened ring reads at under 2:1.
            Image(systemName: badge.icon)
                .font(.system(size: iconSize))
                .foregroundStyle(rarity.chipText)
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - Content

/// Everything the section draws, resolved once per trip set.
private struct AchievementsContent {
    var featured: Badge?
    var isFeaturedPinned = false
    var strip: [Badge] = []
    var overflow = 0
    var unlockedCount = 0
    var totalCount = 0

    /// How many discs fit beside the «+N» capsule at 360pt.
    private static let stripLimit = 6

    /// Pure — safe to run inside `Task.detached`.
    ///
    /// `totalCount` counts what `BadgesView` counts: everything except badges
    /// that are hidden AND still locked. A different denominator would make the
    /// header say «12 из 53» and the screen one tap away say «12/41» about the
    /// same collection.
    static func build(stats: BadgeStats, pinnedId: String?) -> AchievementsContent {
        let unlocked = BadgeManager.unlockedBadges(for: stats)
        let unlockedIds = Set(unlocked.map(\.id))

        var content = AchievementsContent()
        content.unlockedCount = unlocked.count
        content.totalCount = Badge.all.filter { !$0.isHidden || unlockedIds.contains($0.id) }.count
        guard let first = unlocked.first else { return content }

        let pinned = pinnedId.flatMap { id in unlocked.first { $0.id == id } }
        // Strictly-greater, so a tie keeps the earlier badge — i.e. catalogue order.
        let rarest = unlocked.dropFirst().reduce(first) { best, badge in
            badge.displayRarity > best.displayRarity ? badge : best
        }
        let featured = pinned ?? rarest
        content.featured = featured
        content.isFeaturedPinned = pinned != nil

        // Rarest first so the good ones are the ones that fit. `sorted` is not
        // stable, so the catalogue index is the explicit tiebreak inside a tier.
        let rest = unlocked.enumerated()
            .filter { $0.element.id != featured.id }
            .sorted { a, b in
                a.element.displayRarity == b.element.displayRarity
                    ? a.offset < b.offset
                    : a.element.displayRarity > b.element.displayRarity
            }
            .map(\.element)

        content.strip = Array(rest.prefix(stripLimit))
        content.overflow = rest.count - content.strip.count
        return content
    }
}
