import SwiftUI

/// The first thing the «Я» tab shows: who you are, how far you've driven, and
/// the way into Настройки — one coloured card in place of the three flat rows
/// (emoji line, sync line, white stat strip) the screen used to open with.
///
/// Why this replaces the canon header (150:1244): the tab landed as a stack of
/// greys — a 64pt emoji on bare `bg`, a grey «Синхронизация выключена» line, a
/// white strip of numbers, then more white cards — and read as a settings page
/// rather than the place a person's driving lives. Worse, the background picked
/// in «Мой профиль» was drawn on that PUSHED hub only, so the single piece of
/// personalisation in the app never appeared on the screen you actually land
/// on. It does now: the card wears it.
///
/// Everything inside stays its own tap target — avatar/name → «Мой профиль»,
/// pill → «Уровни», numbers → «Статистика», gear → «Настройки» — because a
/// single-target hero would take four destinations away to save one card.
struct ProfileHeroCard: View {
    let background: ProfileBackground
    let avatarEmoji: String
    let name: String
    /// A signed-in account with no name shows a PROMPT here, not a name — it is
    /// drawn dimmer so «Добавьте имя» doesn't impersonate one.
    var isNamePlaceholder: Bool = false
    let level: Int
    let rankTitle: String

    let trips: Int
    let km: Double
    let regions: Int
    /// Zeros read as broken on a fresh install, so the first-launch layout hides
    /// the numbers and lets the welcome card below do the talking.
    var showsStats: Bool = true

    let onTapProfile: () -> Void
    let onTapLevel: () -> Void
    let onTapStats: () -> Void
    let onTapSettings: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    private static let avatarSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityRow
            if showsStats {
                statsRow
                    .padding(.top, 16)
            }
        }
        .padding(16)
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // In the dark theme the page ground is near-black and a shadow buys
        // nothing, so the edge is drawn instead — without it the default
        // gradient's dark corner dissolves into the page.
        .overlay {
            if scheme == .dark {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            }
        }
        // Lifts the card off the page ground the way canon's white cards never
        // needed to: this one is dark, and without the shadow its bottom edge
        // reads as a cut rather than an object.
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 14, y: 6)
    }

    // MARK: - Identity

    private var identityRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                Haptics.tap()
                onTapProfile()
            } label: {
                Text(avatarEmoji)
                    .font(.system(size: 33))
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .background(Circle().fill(.white.opacity(0.18)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_avatar")

            VStack(alignment: .leading, spacing: 7) {
                Button {
                    Haptics.tap()
                    onTapProfile()
                } label: {
                    Text(name)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(.white.opacity(isNamePlaceholder ? 0.7 : 1))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.tap()
                    onTapLevel()
                } label: {
                    heroLvlPill
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile_lvl_pill")
            }

            // 44 keeps the name clear of the gear, which is pinned to the
            // card's top-trailing corner rather than to this row's baseline.
            Spacer(minLength: 44)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                Haptics.tap()
                onTapSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.white.opacity(0.18)))
                    // The tap target stays 44 while the disc reads 36.
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("profile_gear")
            // Nudged out of the padding so the disc lines up with the card's
            // corner radius instead of floating inside it.
            .offset(x: 6, y: -6)
        }
    }

    /// `LvlPill` in hero dress. The shared component paints gold on `goldBg`,
    /// which is a translucent wash — over Ocean or Sunset it turns to mud. Same
    /// gold ink, but on a black scrim, so the rank survives every preset.
    private var heroLvlPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
            Text("LVL \(level)")
                .font(.custom("Handjet-Black", fixedSize: 15))
            Text(rankTitle)
                .font(.custom("Handjet-Black", fixedSize: 15))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(AppTheme.gold)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 3)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(AppTheme.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Stats

    private var statsRow: some View {
        Button {
            Haptics.tap()
            onTapStats()
        } label: {
            HStack(spacing: 0) {
                column(value: "\(trips)", label: AppStrings.trips(lang.language))
                divider
                column(value: GarageFormat.odometer(km), label: AppStrings.statsKmTotal(lang.language))
                divider
                column(value: "\(regions)", label: AppStrings.statsRegions(lang.language))
            }
            .padding(.vertical, 12)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_stats_strip")
    }

    private func column(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 19, weight: .heavy).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.22))
            .frame(width: 1, height: 30)
    }

    // MARK: - Backdrop

    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            if background == .none {
                // The default has to be the best-looking one, not the leftover:
                // most people never open the picker. Ink rather than accent so
                // it doesn't compete with the orange Record button two rows
                // down, with one warm glow in the corner — which is also the
                // only hint on this screen that the surface can carry colour.
                LinearGradient(
                    colors: scheme == .dark
                        // Lifted a stop in the dark theme: the light-theme
                        // values bottom out at 0.09, which IS the dark page.
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
            } else {
                background.view()
            }

            // Legibility floor. `dawn` and `sand` start near-white in the top
            // corner — exactly where the name sits — and every preset ends
            // light enough somewhere to threaten the 10pt stat labels.
            LinearGradient(
                colors: [.black.opacity(0.30), .black.opacity(0.06), .black.opacity(0.28)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}
