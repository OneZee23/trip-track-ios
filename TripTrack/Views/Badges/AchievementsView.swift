import SwiftUI

// MARK: - Достижения (Figma 895:365)

/// The whole badge collection, pushed from the Я tab's achievements section.
/// Replaces the `BadgesView` sheet: same unlock computation and the same
/// denominator, but canon's hero + segment + two-column grid instead of one
/// section per category.
///
/// Owns no navigation. Tapping a tile calls `onTapBadge` and the pusher opens
/// the detail — so this screen can also be dropped into a preview stack.
struct AchievementsView: View {
    let trips: [Trip]
    var onTapBadge: ((Badge) -> Void)? = nil

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @State private var catalogue = AchievementsCatalogue()
    @State private var filter: Filter = .all
    /// «Nothing unlocked yet» and «not walked yet» are the same empty
    /// catalogue, and the walk is async — without this the hero flashes «0 из
    /// 0 открыто» on every mount, including for a user with forty badges.
    @State private var hasLoaded = false

    enum Filter: String, CaseIterable, Hashable {
        case all, unlocked, secret

        func title(_ lang: LanguageManager.Language) -> String {
            switch self {
            case .all:      return AppStrings.achievementsFilterAll(lang)
            case .unlocked: return AppStrings.achievementsFilterUnlocked(lang)
            case .secret:   return AppStrings.achievementsFilterSecret(lang)
            }
        }
    }

    private static let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        ScrollView {
            VStack(spacing: 16) {
                hero(c)
                segment(c)
                grid(c)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            // The app's nav bar, not a local copy: canon draws a 34pt circle
            // and a 28pt title, but every pushed screen this release runs
            // `CustomNavBar` (40pt `NavCircleIcon`, 18pt title), and a screen
            // that sizes its own would read as a different app mid-push.
            CustomNavBar(title: AppStrings.achievementsTitle(lang.language), largeTitle: true)
                .accessibilityIdentifier("achievements_back")
        }
        // Unlocking walks every trip and every badge predicate — once per trip
        // set, never per redraw. `trips.count` is the whole identity: badges
        // are milestone-shaped, so editing an existing trip cannot flip one.
        .task(id: trips.count) { await load() }
        .accessibilityIdentifier("achievements_screen")
    }

    // MARK: - Hero

    private func hero(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                percentRing(c)

                VStack(alignment: .leading, spacing: 4) {
                    Text(hasLoaded
                         ? AppStrings.achievementsOpenedOf(
                            lang.language,
                            unlocked: catalogue.unlockedCount,
                            total: catalogue.totalCount)
                         : "")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Text(AppStrings.achievementsCollectHint(lang.language))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            if !catalogue.rarityRows.isEmpty {
                rarityChips(c)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 20)
        .accessibilityIdentifier("achievements_hero")
    }

    private func percentRing(_ c: AppTheme.Colors) -> some View {
        ZStack {
            // Canon's #FCE4DB is the accent laid over white at 16 %. Written
            // as alpha rather than that hex: over the white card it resolves
            // to the same colour, and on the dark card it stays a wash instead
            // of a near-white slab (same fix as `AppTheme.goldBg`).
            Circle().fill(AppTheme.accent.opacity(0.16))
            Circle().strokeBorder(AppTheme.accent, lineWidth: 4)

            Text(hasLoaded ? "\(catalogue.percent)%" : "")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(AppTheme.accent)
        }
        .frame(width: 72, height: 72)
    }

    /// SwiftUI has no flow layout, so the chips are chunked in code. Two per
    /// row is what canon's own artboard breaks to, and two RU chips
    /// («Легендарных 1» + «Необычных 12») are the widest pair that still fits
    /// the card at 360pt — the narrowest width this screen has to survive.
    private func rarityChips(_ c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(catalogue.rarityRows) { row in
                HStack(spacing: 8) {
                    ForEach(row.items) { item in
                        chip(item, c)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func chip(_ item: RarityCount, _ c: AppTheme.Colors) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.rarity.chipRing)
                .frame(width: 8, height: 8)

            Text(AppStrings.achievementsRarityCount(
                lang.language, rarity: item.rarity, count: item.count))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
        }
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .padding(.vertical, 6)
        .background(item.rarity.rowTint, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Segment

    private func segment(_ c: AppTheme.Colors) -> some View {
        HStack(spacing: 0) {
            ForEach(Filter.allCases, id: \.self) { item in
                Button {
                    guard filter != item else { return }
                    Haptics.selection()
                    filter = item
                } label: {
                    Text(item.title(lang.language))
                        .font(.system(size: 13, weight: filter == item ? .bold : .medium))
                        .foregroundStyle(filter == item ? c.text : c.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 9)
                                .fill(filter == item ? c.card : Color.clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("achievements_filter_\(item.rawValue)")
            }
        }
        .padding(3)
        .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.18), value: filter)
    }

    // MARK: - Grid

    @ViewBuilder
    private func grid(_ c: AppTheme.Colors) -> some View {
        let badges = catalogue.badges(for: filter)

        if badges.isEmpty {
            // Only after the walk: an empty grid before it has run is «not
            // counted yet», not «nothing here».
            if hasLoaded { emptyState(c) }
        } else {
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(badges) { badge in
                    Button {
                        Haptics.tap()
                        onTapBadge?(badge)
                    } label: {
                        AchievementCell(badge: badge, state: catalogue.state(for: badge))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyState(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 10) {
            EmptyStateIllustration(name: "empty_achievements", size: 148)
            Text(AppStrings.achievementsEmpty(lang.language))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.text)

            Text(AppStrings.achievementsEmptyHint(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Data

    private func load() async {
        // `computeStats` reads the streak row off the CoreData view context,
        // so the trip walk stays on the main actor; only the pure pass over
        // the badge catalogue goes off it. Same split as
        // `ProfileAchievementsSection`.
        let stats = BadgeManager.computeStats(from: trips)
        let built = await Task.detached(priority: .userInitiated) {
            AchievementsCatalogue.build(stats: stats)
        }.value
        guard !Task.isCancelled else { return }
        catalogue = built
        hasLoaded = true
    }
}

// MARK: - Chips

/// One hero chip: a tier and how many of it the user holds.
private struct RarityCount: Identifiable {
    let rarity: BadgeRarity
    let count: Int

    var id: Int { rarity.rawValue }
}

/// A chunked row of chips. A wrapper type rather than `[[RarityCount]]` so
/// `ForEach` has a stable identity to hold onto instead of an array index.
private struct RarityChipRow: Identifiable {
    let id: Int
    let items: [RarityCount]
}

// MARK: - Catalogue

/// Everything the screen draws, resolved once per trip set.
private struct AchievementsCatalogue {
    var unlockedIds: Set<String> = []
    var unlockedCount = 0
    var totalCount = 0
    var rarityRows: [RarityChipRow] = []

    /// Canon's grid order: unlocked rarest-first, then the locked ones the
    /// user can read a name off, then the secrets.
    private var allBadges: [Badge] = []
    private var unlockedBadges: [Badge] = []
    private var hiddenBadges: [Badge] = []

    /// How many chips fit a row at 360pt — see `rarityChips`.
    private static let chipsPerRow = 2

    var percent: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(unlockedCount) / Double(totalCount) * 100).rounded())
    }

    func badges(for filter: AchievementsView.Filter) -> [Badge] {
        switch filter {
        case .all:      return allBadges
        case .unlocked: return unlockedBadges
        case .secret:   return hiddenBadges
        }
    }

    func state(for badge: Badge) -> AchievementCellState {
        if unlockedIds.contains(badge.id) { return .unlocked }
        if badge.isHidden { return .secret }
        // No progress: a `Badge` holds a predicate over `BadgeStats`, never
        // the number that predicate compares against, so there is no honest
        // denominator to draw. See `AchievementCellState`.
        return .locked(progress: 0, caption: "")
    }

    /// Pure — safe to run inside `Task.detached`.
    ///
    /// `totalCount` counts what `BadgesView` and `ProfileAchievementsSection`
    /// count: everything except badges that are hidden AND still locked. A
    /// different denominator would make the profile pill say «12 из 32» and
    /// this screen, one tap away, say «12 из 53» about the same collection.
    static func build(stats: BadgeStats) -> AchievementsCatalogue {
        let unlocked = BadgeManager.unlockedBadges(for: stats)
        let ids = Set(unlocked.map(\.id))

        var out = AchievementsCatalogue()
        out.unlockedIds = ids
        out.unlockedCount = unlocked.count
        out.totalCount = Badge.all.filter { !$0.isHidden || ids.contains($0.id) }.count

        // Rarest first so the good ones lead the grid. `sorted` is not stable,
        // so the catalogue index is the explicit tiebreak inside a tier.
        out.unlockedBadges = unlocked.enumerated()
            .sorted { a, b in
                a.element.displayRarity == b.element.displayRarity
                    ? a.offset < b.offset
                    : a.element.displayRarity > b.element.displayRarity
            }
            .map(\.element)

        // «Секретные» is every hidden badge, not every *locked* hidden one —
        // once earned, a secret is a normal tile and hiding it here would lose
        // the only place it can be found by that name.
        out.hiddenBadges = Badge.all.filter(\.isHidden)

        let lockedVisible = Badge.all.filter { !ids.contains($0.id) && !$0.isHidden }
        let lockedHidden = Badge.all.filter { !ids.contains($0.id) && $0.isHidden }
        out.allBadges = out.unlockedBadges + lockedVisible + lockedHidden

        // Chips read the same rarity the tiles do — `displayRarity`, so a
        // badge the backend has re-ranked is counted where it is drawn.
        var counts: [BadgeRarity: Int] = [:]
        for badge in unlocked { counts[badge.displayRarity, default: 0] += 1 }
        let items = counts
            .map { RarityCount(rarity: $0.key, count: $0.value) }
            .sorted { $0.rarity > $1.rarity }
        out.rarityRows = stride(from: 0, to: items.count, by: chipsPerRow).map { start in
            RarityChipRow(
                id: start,
                items: Array(items[start..<min(start + chipsPerRow, items.count)])
            )
        }

        return out
    }
}
