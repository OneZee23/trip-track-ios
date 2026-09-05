import SwiftUI

/// «Уровень машины» (Figma «06 · Авто · Уровень машины (инфо)») — the one place
/// that explains what the LVL number on the vehicle card means.
///
/// Pushed from the level row of `VehicleDetailView`, never presented as a sheet:
/// it is a footnote to that screen, and a sheet would put it beside it instead
/// of behind it.
///
/// Value-driven on purpose — it takes the level and the odometer rather than a
/// vehicle id, so it renders in a preview and in tests without a live
/// `SettingsManager` behind it. Nothing here is interactive but the back button;
/// there is nothing to change, only something to understand.
struct VehicleLevelInfoView: View {
    let level: Int
    let odometerKm: Double

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    /// One row per decade of `VehicleLevelSystem`'s ramp: 0 stands for 1–9,
    /// 1 for 10–19, … and 10 for «100 и выше», where the colour stops changing.
    private static let decades = 0...10

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(c: c, l: l)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    levelCard(c: c, l: l)
                    textSection(
                        title: AppStrings.vehicleLevelHowGrows(l),
                        text: AppStrings.vehicleLevelHowGrowsBody(l),
                        c: c
                    )
                    textSection(
                        title: AppStrings.vehicleLevelAffects(l),
                        text: AppStrings.vehicleLevelAffectsBody(l),
                        c: c
                    )
                    colorsSection(c: c, l: l)
                }
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        .toolbar(.hidden, for: .navigationBar)
        // Same wiring as the detail screen this pushes from — without it the
        // hidden bar takes the interactive pop gesture with it.
        .background(NavBarKiller())
        .accessibilityIdentifier("vehicle_level_info_screen")
    }

    // MARK: - Nav Row

    /// The same bar as everywhere else — this screen is one push from the
    /// vehicle card and any difference between the two would show.
    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        CustomNavBar(title: AppStrings.vehicleLevelTitle(l))
    }

    // MARK: - Level Card

    private func levelCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let color = VehicleLevelSystem.color(for: level)
        let remaining = VehicleLevelSystem.kmToNextLevel(km: odometerKm, level: level)

        return VStack(spacing: 14) {
            // The same atom the detail screen's level row draws, at the size
            // canon gives the hero. This screen exists to explain THAT number,
            // so it has to be the same glyphs in the same colour — a local
            // `Text` in the pixel font would be a look-alike free to drift.
            VehicleLevelPill(level: level, size: 40)

            VehicleXPBar(
                progress: VehicleLevelSystem.progressToNext(km: odometerKm, level: level),
                tint: color
            )

            Text(
                AppStrings.vehicleLevelToNext(
                    l,
                    km: GarageFormat.odometer(remaining, lng: l),
                    level: level + 1
                )
            )
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(c.textTertiary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Prose Sections

    private func textSection(title: String, text: String, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GarageSectionLabel(text: title, size: 11, tracking: 0.36)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Colour Legend

    private func colorsSection(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GarageSectionLabel(text: AppStrings.vehicleLevelColors(l), size: 11, tracking: 0.36)

            VStack(spacing: 0) {
                ForEach(Self.decades, id: \.self) { decade in
                    if decade > 0 {
                        Rectangle()
                            .fill(c.cardAlt)
                            .frame(height: 1)
                    }
                    colorRow(decade: decade, c: c, l: l)
                }
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func colorRow(decade: Int, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // The first decade starts at 1, not 0 — there is no level zero.
        let sample = decade == 0 ? 1 : decade * 10
        // The last decade has no upper bound to print — the colour holds from
        // 100 on, so the row says so instead of inventing a «100–109».
        let range = decade < 10
            ? "\(sample)–\(decade * 10 + 9)"
            : AppStrings.vehicleLevelAndAbove(l, level: sample)

        return HStack(spacing: 12) {
            VehicleLevelPill(level: sample, size: 10)
            Spacer(minLength: 8)
            Text(range)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(c.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
