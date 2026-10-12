import SwiftUI

/// Identity and trip totals on «Me». Chosen covers keep their own artwork.
///
/// The default is the dark ink card with one warm glow (owner, 12 Oct 2026,
/// variant A of three: «серовато как-то, надо чуть выделеннее»). 0.8.8 had
/// made it a white card that followed the theme, and on the warm grey page
/// it lost its one strong contrast: the screen's hero read like every card
/// under it. Ink rather than the accent, so it doesn't compete with the
/// terracotta Record button in the bar; the glow in the corner is also the
/// one hint on this screen that the card can carry colour.
struct ProfileHeroCard: View {
    let background: ProfileBackground
    let avatarEmoji: String
    let name: String
    var isNamePlaceholder: Bool = false
    let level: Int
    let rankTitle: String
    let trips: Int
    let km: Double
    let regions: Int
    var showsStats: Bool = true
    let onTapProfile: () -> Void
    let onTapLevel: () -> Void
    let onTapStats: () -> Void
    let onTapSettings: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.dynamicTypeSize) private var typeSize
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var plus = PlusAccess.shared

    /// A chosen cover, or the dark default: either way the card is dark, and
    /// the type on it is white.
    private var chosenCover: ProfileBackground? {
        let effective = background.effective(isPlus: plus.isPlus)
        return effective == .none ? nil : effective
    }
    private var ink: Color { .white }
    private var secondaryInk: Color { .white.opacity(0.85) }
    private var rule: Color { .white.opacity(0.22) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            identityRow
            if showsStats {
                Rectangle().fill(rule).frame(height: 1)
                statsRow
            }
        }
        .padding(20)
        .background {
            if let chosenCover {
                chosenCover.view()
                    .overlay(.black.opacity(0.64))
            } else {
                defaultBackdrop
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // In the dark theme the page is near-black: without an edge the card's
        // dark corner dissolves into it.
        .overlay {
            if scheme == .dark {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
        }
    }

    /// Ink with one warm glow — the pre-0.8.8 default, kept to the numbers it
    /// had: the dark theme starts a stop lighter, because the light-theme
    /// gradient bottoms out at 0.09, which IS the dark page.
    private var defaultBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.26, green: 0.27, blue: 0.32),
                       Color(red: 0.15, green: 0.15, blue: 0.18)]
                    : [Color(red: 0.20, green: 0.21, blue: 0.25),
                       Color(red: 0.09, green: 0.09, blue: 0.11)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [AppTheme.accent.opacity(0.55), .clear],
                center: UnitPoint(x: 0.88, y: 0.02),
                startRadius: 4,
                endRadius: 250
            )
        }
    }

    private var identityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    Haptics.tap()
                    onTapProfile()
                } label: {
                    Text(avatarEmoji)
                        .font(.inter(32))
                        .frame(width: 60, height: 60)
                        .background(.white.opacity(0.16), in: Circle())
                        .avatarFrame(
                            AvatarFrame.effective(id: settings.avatarFrame, isPlus: plus.isPlus),
                            lineWidth: 3)
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.myProfileTitle(lang.language))
                .accessibilityIdentifier("profile_avatar")

                if !typeSize.isAccessibilitySize {
                    identityText
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                Button {
                    Haptics.tap()
                    onTapSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityLabel(AppStrings.settingsTitle(lang.language))
                .accessibilityIdentifier("profile_gear")
            }
            if typeSize.isAccessibilitySize { identityText }
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Haptics.tap()
                onTapProfile()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name)
                        .font(.interScaled(21, weight: .bold, relativeTo: .title3))
                        .tracking(-0.3)
                        .foregroundStyle(isNamePlaceholder ? secondaryInk : ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if PlusBadgeVisibility.shows(isPlus: plus.isPlus, isOwn: true,
                                                showsOwnBadge: settings.showPlusBadge) {
                        ProBadge(height: 16)
                    }
                }
                .frame(minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.tap()
                onTapLevel()
            } label: {
                HStack(spacing: 5) {
                    Text("LVL \(level)")
                        .font(.custom("Handjet-Black", size: 17, relativeTo: .subheadline))
                        .foregroundStyle(.white)
                    Text(rankTitle)
                        .font(.interScaled(12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(secondaryInk)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_lvl_pill")
        }
    }

    private var statsRow: some View {
        Button {
            Haptics.tap()
            onTapStats()
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                column(value: "\(trips)", label: AppStrings.trips(lang.language))
                column(value: Measure.distanceValue(km: km, unit: distanceUnit, lang: lang.language),
                       label: AppStrings.statsKmTotal(lang.language, unit: distanceUnit))
                column(value: "\(regions)", label: AppStrings.statsRegions(lang.language))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("profile_stats_strip")
    }

    private func column(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.interScaled(22, weight: .bold, relativeTo: .title3).monospacedDigit())
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.interScaled(11, weight: .medium, relativeTo: .caption))
                .foregroundStyle(secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
