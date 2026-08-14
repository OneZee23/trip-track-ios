import SwiftUI
// UIColor only, and only for `rankInk` — reading a fixed Color's hue back out
// has no SwiftUI equivalent on iOS 17 (`Color.mix` is 18+).
import UIKit

/// «Уровни» (Figma 888:3848) — the one screen that explains the driver level:
/// where you stand, how XP is actually earned, and the whole ladder above you.
///
/// Replaces two surfaces at once: the `DriverLevelView` card with its
/// expand-to-read footnote, and the `RankProgressSheet` bottom sheet. Both are
/// left in place for their current callers; this one is the pushed screen the
/// Я tab links to, so it carries the nav bar rather than a grabber.
///
/// Read-only, and parameterless on purpose — the level and XP are global facts
/// about the account (`SettingsManager`), not something a caller gets to hand
/// in and get wrong.
///
/// Every number here is mirrored from `GamificationManager.calculateXP`. If
/// that formula changes, the «Как получать опыт» card is a lie until it is
/// changed too: people read this screen and then drive to earn what it promises.
struct LevelsView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @ObservedObject private var settings = SettingsManager.shared

    /// A rule as the card draws it: the multiplier chip is notation (a sign and
    /// a number, identical in both languages and taken straight from
    /// `calculateXP`), the sentence beside it is prose and lives in AppStrings.
    private struct XPRule: Identifiable {
        let badge: String
        let text: String
        var id: String { badge }
    }

    // MARK: - Derived state

    /// Stored level is trusted (it is what the rest of the app shows) but
    /// clamped: `DriverRank.from` falls back to «Новичок» for anything outside
    /// 1…110, which would paint a level-0 profile as rank 1 of 14 with a full bar.
    private var level: Int { min(max(settings.profileLevel, 1), LevelSystem.maxLevel) }
    private var xp: Int { settings.profileXP }
    private var rank: DriverRank { DriverRank.from(level: level) }
    private var isMaxLevel: Bool { level >= LevelSystem.maxLevel }

    private var rankIndex: Int { (DriverRank.allCases.firstIndex(of: rank) ?? 0) + 1 }

    /// The rank after this one, or nil at «Вечный странник».
    private var nextRank: DriverRank? {
        let next = rankIndex  // rankIndex is 1-based, so it already points one past
        return next < DriverRank.allCases.count ? DriverRank.allCases[next] : nil
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        ScrollView {
            VStack(spacing: 16) {
                heroCard(c, l)
                howToEarnCard(c, l)
                ladderCard(c, l)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        .hideAppTabBar()
        .safeAreaInset(edge: .top, spacing: 0) {
            // The app's own bar. The id rides on it because the back circle is
            // shared code and the only button in there — same as Статистика.
            CustomNavBar(title: AppStrings.levelsTitle(l), largeTitle: true)
                .accessibilityIdentifier("levels_back")
        }
        .accessibilityIdentifier("levels_screen")
    }

    // MARK: - Hero

    private func heroCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let ink = rankInk(rank)

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                levelDisc(ink)

                VStack(alignment: .leading, spacing: 4) {
                    Text(rank.title(l))
                        .font(.system(size: 21, weight: .heavy))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        // «Покоритель дорог» at 21 heavy overruns the 360pt
                        // artboard's own hero, let alone a small phone.
                        .minimumScaleFactor(0.7)

                    Text(AppStrings.levelsRankOf(
                        l,
                        rank: rankIndex,
                        total: DriverRank.allCases.count,
                        level: level
                    ))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }

            progressBlock(c, l, ink: ink)
            nextRankPill(c, l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .surfaceCard(cornerRadius: 20)
        .accessibilityIdentifier("levels_hero")
    }

    /// The level itself.
    ///
    /// NOT Handjet, despite the LVL pill using it. Handjet is extremely
    /// condensed: «LVL 12» reads fine because five glyphs give the eye a word
    /// to lock onto, but ONE digit alone at 27pt renders as a thin vertical bar
    /// — on device the «8» here was unreadable. Canon draws this number as a
    /// plain heavy numeral, and a number the whole screen exists to explain has
    /// to be legible before it is stylish.
    private func levelDisc(_ ink: Color) -> some View {
        ZStack {
            Circle().fill(rankTint(ink))
            Circle().strokeBorder(ink, lineWidth: 3.5)
            Text("\(level)")
                .font(.system(size: 26, weight: .heavy).monospacedDigit())
                .minimumScaleFactor(0.6)   // three digits still fit at level 100+
                .lineLimit(1)
                .foregroundStyle(ink)
                .padding(.horizontal, 6)
        }
        .frame(width: 64, height: 64)
    }

    private func progressBlock(
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language,
        ink: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VehicleXPBar(
                // The bar has to mean what the caption under it says. `progressToNextLevel`
                // is progress WITHIN the level (xp − thisThreshold) / (next − thisThreshold),
                // which drew 41.8 % under a caption reading «1 951 / 2 300 XP» = 84.8 %.
                // Canon is the absolute ratio: its «6 100 / 6 600 XP» sits under a bar
                // filled 92 %.
                progress: isMaxLevel
                    ? 1
                    : min(1, Double(xp) / Double(max(1, LevelSystem.xpForNextLevel(level)))),
                tint: ink,
                height: 10
            )

            HStack(alignment: .top, spacing: 8) {
                Text(isMaxLevel
                     ? AppStrings.levelsXpTotal(l, xp: GarageFormat.odometer(Double(xp)))
                     : AppStrings.levelsXpProgress(
                        l,
                        current: GarageFormat.odometer(Double(xp)),
                        target: GarageFormat.odometer(Double(LevelSystem.xpForNextLevel(level)))
                     ))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(c.text)

                Spacer(minLength: 0)

                Text(isMaxLevel
                     ? AppStrings.levelsMaxLevel(l)
                     : AppStrings.levelsToNextLevel(l, level: level + 1))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func nextRankPill(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        // Tinted by the rank it names, not the current one: the pill is the
        // first sight of the colour the whole screen turns at the next rank.
        let ink = rankInk(nextRank ?? rank)
        let text = nextRank.map {
            AppStrings.levelsNextRank(l, rank: $0.title(l), level: $0.levelRange.lowerBound)
        } ?? AppStrings.levelsFinalRank(l)

        return HStack(spacing: 8) {
            Circle()
                .fill(ink)
                .frame(width: 9, height: 9)

            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rankTint(ink), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Как получать опыт

    /// The rules `calculateXP` actually applies, checked against it line by
    /// line. They stack: a first trip of the day into a new region, 200 km
    /// long, collects every one of them.
    ///
    /// The region row names TWO awards because the code grants two — a flat
    /// +50 and half the base distance XP again (`newRegionBonus = base / 2`).
    /// Canon's card prints only the +50; a screen whose whole job is explaining
    /// the formula must not undercount it.
    private func rules(_ l: LanguageManager.Language) -> [XPRule] {
        [
            XPRule(badge: AppStrings.levelsRuleKmBadge(l), text: AppStrings.levelsRuleKm(l)),
            XPRule(badge: AppStrings.levelsRuleFirstBadge(l), text: AppStrings.levelsRuleFirst(l)),
            XPRule(badge: AppStrings.levelsRuleRegionBadge(l), text: AppStrings.levelsRuleRegion(l)),
            XPRule(badge: AppStrings.levelsRuleLongBadge(l), text: AppStrings.levelsRuleLong(l)),
        ]
    }

    private func howToEarnCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionLabel(text: AppStrings.levelsHowToEarn(l))

            ForEach(rules(l)) { rule in
                HStack(spacing: 12) {
                    Text(rule.badge)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .lineLimit(1)
                        .padding(.vertical, 5)
                        // Fixed width so the four chips line up their right
                        // edges and the sentences start on one column.
                        .frame(width: 54)
                        .background(AppTheme.accentBg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(rule.text)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(c.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceCard(cornerRadius: 20)
    }

    // MARK: - Все ранги

    private func ladderCard(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                ProfileSectionLabel(text: AppStrings.levelsAllRanks(l))
                Spacer()
                Text("\(DriverRank.allCases.count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.leading, 4)
            .padding(.bottom, 6)

            ForEach(DriverRank.allCases, id: \.self) { r in
                ladderRow(r, c, l)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .surfaceCard(cornerRadius: 20)
    }

    /// Ranks below the current one are not ticked off and ranks above are not
    /// locked: the ladder is one continuous thing to climb, and only the rung
    /// you are standing on is marked.
    private func ladderRow(
        _ r: DriverRank,
        _ c: AppTheme.Colors,
        _ l: LanguageManager.Language
    ) -> some View {
        let ink = rankInk(r)
        let isCurrent = r == rank

        return HStack(spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(ink)
                    .frame(width: 11, height: 11)

                Text(r.title(l))
                    .font(.system(size: 14, weight: isCurrent ? .bold : .semibold))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isCurrent {
                    // Caps by the canon's hand, not the translator's: a 10pt
                    // tracked label reads as a marker only in caps.
                    Text(AppStrings.levelsCurrentMarker(l))
                        .font(.system(size: 10, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }

            Spacer(minLength: 8)

            Text(AppStrings.levelsRankRange(
                l,
                from: r.levelRange.lowerBound,
                to: r.levelRange.upperBound
            ))
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(c.textSecondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isCurrent ? rankTint(ink) : .clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityIdentifier("levels_rank_row")
    }

    // MARK: - Rank ink

    /// `DriverRank.color` is a light-theme ramp on purpose — it deepens toward
    /// oxblood so a higher rank reads as hotter, and the top of it (#6F162F →
    /// #421021) is very nearly black. On the dark card that ink disappears, and
    /// the four ranks a player has the furthest to climb toward would be four
    /// rows of nothing. Dark mode keeps each rank's hue and lifts it into the
    /// readable band instead of flattening the whole ladder to one grey.
    private func rankInk(_ r: DriverRank) -> Color {
        guard scheme == .dark else { return r.color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(r.color).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return r.color
        }
        // Floors, not a scale: the pale end of the ramp is already bright
        // enough and must not blow out into neon.
        return Color(
            hue: Double(hue),
            saturation: Double(min(saturation, 0.68)),
            brightness: Double(max(brightness, 0.70))
        )
    }

    /// The wash behind a rank's own colour — the hero disc, the next-rank pill,
    /// the current row. Slightly heavier in the dark, where an 8% veil over a
    /// near-black card is invisible.
    private func rankTint(_ ink: Color) -> Color {
        ink.opacity(scheme == .dark ? 0.18 : 0.14)
    }
}
