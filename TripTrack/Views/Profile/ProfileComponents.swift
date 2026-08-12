import SwiftUI

// MARK: - LVL Pill (Figma 113:53)

/// Gold rank pill under the profile name: «★ LVL 12 Путешественник».
/// FK-13: Figma wants Handjet Black 15 — the app deliberately ships no
/// Handjet family, so system heavy 15 stands in.
struct LvlPill: View {
    let level: Int
    let rankTitle: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
            Text("LVL \(level)")
                .font(.system(size: 15, weight: .heavy).monospacedDigit())
            Text(rankTitle)
                .font(.system(size: 15, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(AppTheme.gold)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .background(AppTheme.goldBg, in: Capsule())
    }
}

// MARK: - Stats Strip (Figma 150:1244)

/// Three equal columns «47 поездок · 2 430 км всего · 8 регионов» in one
/// white card. The whole strip is a single tap target (entry to Статистика).
struct ProfileStatsStrip: View {
    let trips: Int
    let km: Double
    let regions: Int
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 0) {
                column(value: "\(trips)", label: AppStrings.trips(lang.language), c: c)
                divider(c)
                column(value: GarageFormat.odometer(km), label: AppStrings.statsKmTotal(lang.language), c: c)
                divider(c)
                column(value: "\(regions)", label: AppStrings.statsRegions(lang.language), c: c)
            }
            .padding(.vertical, 14)
            .surfaceCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_stats_strip")
    }

    private func column(value: String, label: String, c: AppTheme.Colors) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy).monospacedDigit())
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func divider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(width: 1, height: 34)
    }
}

// MARK: - Moment Card (Figma 150:1244 «Моменты»)

/// Horizontal-rail gradient card: bottom-aligned title + subtitle over a
/// full-bleed gradient. Gradients intentionally identical in dark mode.
struct MomentCard: View {
    let title: String
    let subtitle: String
    let gradient: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white)
                .lineSpacing(1.2)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .frame(width: 154, height: 120, alignment: .bottomLeading)
        .background(gradient, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - History Trip Row (Figma 150:1244 «История»)

/// White trip row: 70×46 route thumbnail, title, «14 апр · Honda Civic ·
/// 158 км» meta, trailing privacy glyph (lock = private, globe = public).
struct ProfileTripRow: View {
    let trip: Trip
    let vehicleName: String?
    /// Who was driving — set ONLY by `WithMeSection` for a «Со мной» row
    /// (a trip that isn't the viewer's own). Takes priority over
    /// `vehicleName` in the meta line when present: naming the driver is
    /// the one fact that tells a companion row apart from the viewer's own
    /// history, where the car matters more than "who else was in it"
    /// (there usually isn't anyone to name). `historySection`'s own rows
    /// never pass this, so their meta line is byte-identical to before.
    var driverName: String? = nil
    let onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 10) {
                LightRoutePreview(coordinates: trip.previewCoordinates, accentColor: AppTheme.accent)
                    .frame(width: 70, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text(metaText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if trip.isPrivate {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(c.textTertiary)
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 15))
                        .foregroundStyle(AppTheme.green)
                }
            }
            .padding(10)
            .surfaceCard(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile_trip_row")
    }

    private var titleText: String {
        if let t = trip.title, !t.isEmpty { return t }
        if let r = trip.region, !r.isEmpty { return r }
        return ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)
    }

    private var metaText: String {
        var parts: [String] = [ProfileDateFormat.dayMonth(trip.startDate, lang: lang.language)]
        if let driverName, !driverName.isEmpty {
            parts.append(driverName)
        } else if let vehicleName, !vehicleName.isEmpty {
            parts.append(vehicleName)
        }
        parts.append("\(GarageFormat.odometer(trip.distanceKm)) \(AppStrings.km(lang.language))")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Section Label

/// «Моменты» / «История» — 16 heavy section header.
struct ProfileSectionLabel: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(text)
            .font(.system(size: 16, weight: .heavy))
            .tracking(-0.16)
            .foregroundStyle(c.text)
    }
}

// MARK: - Settings Icon Row (Figma 154:1365 row master)

/// Settings-sheet row: 30×30 rounded icon square, 14.5-semibold label,
/// arbitrary trailing slot (Toggle / value text / chevron). Deliberately NOT
/// `AccountSettingsRow` — that master (22pt bare icon + subtitle) belongs to
/// CloudSyncView; this one matches the Я-tab settings geometry.
struct SettingsIconRow<Trailing: View>: View {
    let icon: String
    /// When set, renders a bundled template asset instead of an SF Symbol
    /// (Telegram / YouTube / GitHub rows).
    var assetIcon: String?
    var iconColor: Color = AppTheme.accent
    var iconBg: Color = AppTheme.accentBg
    let title: String
    var action: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let row = HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBg)
                if let assetIcon {
                    Image(assetIcon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(iconColor)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(iconColor)
                }
            }
            .frame(width: 30, height: 30)

            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .contentShape(Rectangle())

        if let action {
            Button {
                Haptics.tap()
                action()
            } label: {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }
}

/// Trailing chevron for `SettingsIconRow`.
struct SettingsRowChevron: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 18 * 0.72, weight: .semibold))
            .foregroundStyle(AppTheme.colors(for: scheme).textTertiary)
            .frame(width: 18, height: 18)
    }
}

/// Trailing value text («км», «Русский», «Системная») for `SettingsIconRow`.
struct SettingsRowValue: View {
    let text: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppTheme.colors(for: scheme).textSecondary)
            .lineLimit(1)
    }
}

// MARK: - Shared date formatting

enum ProfileDateFormat {
    private static let ruDayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        // ICU's RU abbreviated months carry a trailing period («апр.») —
        // the canon (Figma 150:1329) and the Статистика chart labels are
        // dotless, so strip it from the symbols the "MMM" field reads.
        f.shortMonthSymbols = f.shortMonthSymbols.map {
            $0.replacingOccurrences(of: ".", with: "")
        }
        return f
    }()
    private static let enDayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM d"
        return f
    }()
    private static let ruMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL"
        return f
    }()
    private static let enMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "LLLL"
        return f
    }()

    /// «14 апр» / "Apr 14" — same convention as StatsView.computeRecords.
    static func dayMonth(_ date: Date, lang: LanguageManager.Language) -> String {
        (lang == .ru ? ruDayMonth : enDayMonth).string(from: date)
    }

    /// «Апрель» / "April" — capitalized standalone month name.
    static func monthName(_ date: Date, lang: LanguageManager.Language) -> String {
        (lang == .ru ? ruMonth : enMonth).string(from: date).capitalized
    }
}
