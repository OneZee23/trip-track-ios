import SwiftUI

// MARK: - Cell state (Figma 896:383 / 897:382 / 897:389)

/// Which of the three tiles canon draws for a badge.
///
/// `locked` carries its progress from the caller because the catalogue has
/// nowhere to keep it: a `Badge` stores `checkUnlocked` — a predicate over
/// `BadgeStats` — and never the target that predicate compares against. So
/// «2 430 / 10 000 км» is only expressible for a badge whose owner already
/// knows the target; everything else passes `(0, "")` and the tile drops the
/// bar rather than drawing an invented denominator.
enum AchievementCellState {
    case unlocked
    case locked(progress: Double, caption: String)
    case secret
}

// MARK: - Cell

/// One tile of the achievements grid. Owns nothing — the screen decides which
/// state a badge is in, this only draws it.
struct AchievementCell: View {
    let badge: Badge
    let state: AchievementCellState

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    /// Canon pins the secret tile at 145pt and lets the others size to content,
    /// which on device makes a two-line RU title stand a tile taller than the
    /// one beside it. Every tile takes 145 as a shared floor and asks to fill
    /// the row, so the three states line up whatever their content is.
    private static let height: CGFloat = 145

    /// Canon: 92pt inside a 158pt tile. A ratio, not a width — the tile is
    /// 20–35pt wider on every phone this ships to.
    private static let barWidthRatio: CGFloat = 0.66

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        content(c)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity)
            .background(background(c))
            .overlay(border(c))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("achievement_cell")
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ c: AppTheme.Colors) -> some View {
        switch state {
        case .unlocked:
            unlockedContent(c)
        case let .locked(progress, caption):
            lockedContent(c, progress: progress, caption: caption)
        case .secret:
            secretContent(c)
        }
    }

    private func unlockedContent(_ c: AppTheme.Colors) -> some View {
        let rarity = badge.displayRarity
        return VStack(spacing: 8) {
            disc(fill: rarity.chipTint) {
                // The glyph takes the darkened ring, not `badge.color`: a
                // per-badge hue inside a per-rarity disc puts two unrelated
                // colour systems in one 56pt circle (see `BadgeRarityChip`).
                Image(systemName: badge.icon)
                    .font(.system(size: 27))
                    .foregroundStyle(rarity.chipText)
            }

            Text(badge.title(lang.language))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 5) {
                Circle()
                    .fill(rarity.chipRing)
                    .frame(width: 7, height: 7)

                Text(shareLine(rarity))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(rarity.chipText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func lockedContent(_ c: AppTheme.Colors, progress: Double, caption: String) -> some View {
        VStack(spacing: 8) {
            // `border` is the faintest ink token, which over `cardAlt` lands on
            // canon's #EBE8E5 — a disc a shade darker than the tile, not a grey
            // of its own.
            disc(fill: c.border) {
                Image(systemName: badge.icon)
                    .font(.system(size: 27))
                    .foregroundStyle(c.text.opacity(0.4))
            }

            Text(badge.title(lang.language))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // No caption means no measurable progress — an empty track would
            // read as "0 % done" when the truth is "we don't count this one".
            if !caption.isEmpty {
                progressBar(c, progress: progress)

                Text(caption)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    private func secretContent(_ c: AppTheme.Colors) -> some View {
        VStack(spacing: 8) {
            disc(fill: c.border) {
                Text(verbatim: "?")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(c.textTertiary)
            }

            Text(AppStrings.achievementsSecretTitle(lang.language))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(c.textSecondary)

            Text(AppStrings.achievementsSecretCaption(lang.language))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
    }

    // MARK: - Pieces

    private func disc<Content: View>(fill: Color, @ViewBuilder glyph: () -> Content) -> some View {
        ZStack {
            Circle().fill(fill)
            glyph()
        }
        .frame(width: 56, height: 56)
    }

    private func progressBar(_ c: AppTheme.Colors, progress: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width * Self.barWidthRatio
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(c.borderBright)
                    .frame(width: width, height: 6)

                Capsule()
                    .fill(c.textTertiary)
                    .frame(width: width * min(max(progress, 0), 1), height: 6)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 6)
    }

    // MARK: - Skin

    @ViewBuilder
    private func background(_ c: AppTheme.Colors) -> some View {
        switch state {
        case .unlocked:
            // The glow is the tier's own hue — it is the only thing separating
            // a legendary tile from a common one at a glance on a warm card.
            RoundedRectangle(cornerRadius: 16)
                .fill(c.card)
                .shadow(color: badge.displayRarity.chipRing.opacity(0.35), radius: 7)
        case .locked, .secret:
            RoundedRectangle(cornerRadius: 16)
                .fill(c.cardAlt)
        }
    }

    @ViewBuilder
    private func border(_ c: AppTheme.Colors) -> some View {
        switch state {
        case .unlocked:
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(badge.displayRarity.chipRing, lineWidth: 1.5)
        case .locked:
            EmptyView()
        case .secret:
            // Canon's #D1CFCC is a mid grey against the tile it dashes, which
            // `borderBright` (8 % ink) is too faint to be — half of the
            // tertiary ink lands on it and keeps a dark twin.
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    c.textTertiary.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
        }
    }

    // MARK: - Copy

    /// «Получили 0,4%» only when the backend actually reported a share. The
    /// field is nil for nearly every badge, and a made-up percentage is a
    /// number the user cannot check — so the slot falls back to the rarity
    /// word, which is authored and always true.
    private func shareLine(_ rarity: BadgeRarity) -> String {
        guard let percent = badge.globalUnlockPercent else {
            return rarity.title(lang.language)
        }
        return AppStrings.achievementsEarnedBy(
            lang.language,
            percent: Badge.unlockShareText(percent, lang.language)
        )
    }

}
