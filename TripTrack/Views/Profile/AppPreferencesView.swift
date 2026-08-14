import SwiftUI

/// «Единицы и формат» — the once-per-install half of the settings sheet, one
/// level down.
///
/// «Единицы» and «Средняя скорость» are both set once and then never touched
/// again, and while they sat in the root card they cost two of the six rows a
/// user reads every time they open Настройки. They are not deleted and not
/// merged into someone else's picker — they are re-homed behind one row that
/// says what is inside it and shows the current unit on its right edge, so the
/// answer to «в чём считает?» is still readable without opening anything.
///
/// Built for more than the two rows it has: date format and 12/24h land here
/// when they exist, which is why this is a screen with a card rather than a
/// third picker sheet.
///
/// Presented as a sheet FROM the settings sheet, exactly like `CloudSyncView`
/// and `DebugLogsView` — a push would have to travel through ProfileView's
/// `mePath`, which means closing the sheet and posting a notification, the very
/// hack the «Страна» row was carrying and this pass removed.
struct AppPreferencesView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"

    @State private var showUnitsPicker = false
    @State private var showAvgSpeedPicker = false

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(l)

            ScrollView {
                VStack(spacing: 4) {
                    card(c, l)
                    footnote(c, l)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 26)
            }
            .scrollIndicators(.hidden)
        }
        .background(c.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("app_prefs_screen")
        .sheet(isPresented: $showUnitsPicker) {
            unitsPicker(l)
        }
        .sheet(isPresented: $showAvgSpeedPicker) {
            avgSpeedPicker(l)
        }
    }

    // MARK: - Chrome

    /// The settings sheet's own header, to the point: title 22 heavy on the
    /// leading side, a flat grey close disc on the trailing one. A nested sheet
    /// that headed itself differently would read as a screen from another app.
    private func navRow(_ l: LanguageManager.Language) -> some View {
        HStack(alignment: .center) {
            Text(AppStrings.settingsAppPrefs(l))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(AppTheme.colors(for: scheme).text)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                SheetCloseCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.closeSheet(l))
            .accessibilityIdentifier("app_prefs_close")
        }
        .padding(.horizontal, 18)
        // The grabber UIKit draws over the sheet's top edge lands on the first
        // ~10pt, so the row starts below it.
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func rowDivider(_ c: AppTheme.Colors) -> some View {
        Rectangle()
            .fill(c.borderBright)
            .frame(height: 1)
    }

    // MARK: - Card

    private func card(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        let isRu = l == .ru
        return VStack(spacing: 0) {
            SettingsIconRow(
                icon: "ruler",
                title: AppStrings.settingsUnits(l),
                action: { showUnitsPicker = true }
            ) {
                SettingsRowValue(text: GarageFormat.distanceShort(distanceUnit, isRu: isRu))
            }
            .accessibilityIdentifier("settings_units")

            rowDivider(c)

            SettingsIconRow(
                icon: "speedometer",
                title: AppStrings.settingsAvgSpeed(l),
                action: { showAvgSpeedPicker = true }
            ) {
                SettingsRowValue(text: settings.avgSpeedMode == .overall
                                 ? AppStrings.avgSpeedOverall(l)
                                 : AppStrings.avgSpeedMoving(l))
            }
            .accessibilityIdentifier("settings_avg_speed")
        }
        .surfaceCard(cornerRadius: 16)
    }

    /// Under the card, not inside it — the same 11.5 / tertiary caption
    /// `SettingsOptionPicker` closes with, so the row and the sheet it opens
    /// speak in one voice.
    private func footnote(_ c: AppTheme.Colors, _ l: LanguageManager.Language) -> some View {
        Text(AppStrings.appPrefsFootnote(l))
            .font(.system(size: 11.5))
            .foregroundStyle(c.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    // MARK: - Pickers (Figma 1685:119)

    private func unitsPicker(_ l: LanguageManager.Language) -> some View {
        SettingsOptionPicker(
            title: AppStrings.settingsUnits(l),
            options: DistanceUnit.allCases,
            selection: DistanceUnit(rawValue: distanceUnit) ?? .km,
            footnote: AppStrings.unitsPickerFootnote(l),
            // The SYMBOL, not the word: `distanceShort` answers «миль» in RU, and
            // four glyphs do not fit a 32pt badge. The row's own value below
            // still uses the localized word, as canon draws it.
            badge: { $0 == .miles ? "mi" : "km" },
            label: { l == .ru ? $0.labelFull.ru : $0.labelFull.en },
            onSelect: { distanceUnit = $0.rawValue },
            accessibilityPrefix: "settings_units"
        )
    }

    /// Canon draws no picker for this row because canon draws no row — the
    /// setting is ours (see the card of this screen). It gets the same sheet as
    /// the three that are drawn, because it is the same KIND of thing: a choice
    /// between named alternatives, not a question with an answer and a cancel.
    /// It spent a while as a confirm dialog, which put an orange «Overall»
    /// button and a «Cancel» under a title — a modal asking permission to
    /// change a preference.
    private func avgSpeedPicker(_ l: LanguageManager.Language) -> some View {
        SettingsOptionPicker(
            title: AppStrings.avgSpeedModeTitle(l),
            options: [AvgSpeedMode.overall, .moving],
            selection: settings.avgSpeedMode,
            footnote: AppStrings.avgSpeedPickerFootnote(l),
            // What each one MEASURES: a clock over the whole trip, a car only
            // while it moved.
            badge: { $0 == .overall ? "clock.fill" : "car.fill" },
            badgeIsSymbol: true,
            label: { $0 == .overall ? AppStrings.avgSpeedOverall(l) : AppStrings.avgSpeedMoving(l) },
            onSelect: { settings.avgSpeedMode = $0 },
            accessibilityPrefix: "settings_avg_speed"
        )
    }
}
