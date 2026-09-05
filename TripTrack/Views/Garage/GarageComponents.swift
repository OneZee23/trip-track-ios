import SwiftUI

// MARK: - Circle Nav Button (Figma "navb" style)

/// 34pt white-circle navigation button used by the custom Garage nav rows.
struct GarageCircleNavButton: View {
    let systemImage: String
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Button {
            Haptics.tap()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(c.card)
                    .shadow(
                        color: scheme == .dark ? .clear : .black.opacity(0.03),
                        radius: 2,
                        y: 1
                    )
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
            }
            .frame(width: 34, height: 34)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vehicle XP Bar

/// Capsule progress bar fed by `progressToNextLevel`.
///
/// The track is the tint's own ghost, not the neutral `cardAlt` it used to be.
/// A grey fill (levels 1–9) on a grey track was one grey slab where the filled
/// part could not be told from the empty part; a track made of the same hue
/// keeps the contrast wherever the decade ramp goes. Solid, not a gradient —
/// the gradient faded the leading edge and made short progress look shorter.
struct VehicleXPBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Sheet Close

/// The «×» in a sheet header: a small grey disc, not the nav bar's control.
///
/// `NavCircleIcon` is a 40pt white circle with a shadow — right for a bar that
/// has to hold its own against a screen, far too loud for a header whose job
/// is to name the sheet. Canon draws this one grey, quiet and half the weight.
struct SheetCloseCircle: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Image(systemName: "xmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(c.textSecondary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(c.cardAlt))
            // Grown to the 44pt floor, then taken back out of layout.
            .padding(7)
            .contentShape(Circle())
            .padding(-7)
    }
}

// MARK: - Plate Chip

/// The registration plate, drawn the same way for every country.
///
/// No flags, no blue EU band, no country-specific skin. A plate chip that
/// dresses itself up as a German or Russian plate has to guess which one it is,
/// and the guess is wrong often enough to look broken — the research that
/// killed input masks kills plate skins for the same reason. One neutral chip
/// reads as "this is the plate" everywhere.
/// It is a plate, so it is drawn like one: dark characters on a light plate
/// with a thin frame, small and tight. The first cut filled it with `cardAlt`
/// and greyed the text, which on the warm card read as a disabled pill twice
/// the size of the number it carried.
struct VehiclePlateChip: View {
    let plate: String
    var size: CGFloat = 11

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(plate)
            .font(.system(size: size, weight: .semibold))
            .tracking(0.3)
            .foregroundStyle(c.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(c.card, in: RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(c.border, lineWidth: 1)
            }
            .fixedSize()
    }
}

// MARK: - Level Pill

/// «LVL 28» in the colour of its decade.
///
/// `fixedSize:` rather than `size:` — `Font.custom(_:size:)` scales with the
/// system text-size setting while `.system(size:)` does not, so on a phone set
/// below the default the pixel font shrank away from the text around it.
struct VehicleLevelPill: View {
    let level: Int
    var size: CGFloat = 8

    var body: some View {
        Text("LVL \(level)")
            .font(.custom("PressStart2P-Regular", fixedSize: size))
            .foregroundStyle(VehicleLevelSystem.color(for: level))
            .fixedSize()
    }
}

// MARK: - Section Label

/// Uppercased tracking section label («СТИКЕРЫ», «РАСХОД ТОПЛИВА», …).
///
/// The 10pt/0.5 default is canon for in-card labels and for «РАСХОД ТОПЛИВА»
/// (499:193), but the screen-level «Стикеры» header is drawn a step larger —
/// 12pt/0.36 in both 119:968 and 499:158 — and rendering it at the in-card
/// size flattened the two levels into one. Size and tracking are independent
/// because canon does not scale one from the other.
struct GarageSectionLabel: View {
    let text: String
    var color: Color?
    var size: CGFloat = 10
    var tracking: CGFloat = 0.5

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(text).textCase(.uppercase)
            .font(.system(size: size, weight: .bold))
            .tracking(tracking)
            .foregroundStyle(color ?? c.textTertiary)
    }
}

// MARK: - Shared Garage formatting

enum GarageFormat {
    /// «38 420» — пробег с разбивкой по разрядам ПО ЯЗЫКУ.
    ///
    /// Единственная функция этого enum'а, которая раньше не принимала язык, —
    /// и при этом самая заметная: паспорт машины делает пробег главным числом
    /// экрана. Русский разделитель разрядов уезжал на немецкие и английские
    /// телефоны, где ждут «38,420» или «38.420».
    ///
    /// Форматирование делегировано `AppStrings.groupedNumber`, где таблица
    /// форматтеров на тринадцать языков уже есть, — второй такой заводить
    /// незачем, а разъехаться они бы разъехались.
    static func odometer(_ km: Double, lng: LanguageManager.Language) -> String {
        AppStrings.groupedNumber(Int(km.rounded()), lng)
    }

    /// Retired FuelSettingsCard's proven display format: integral values drop
    /// the fraction, others keep one decimal; RU uses a decimal comma.
    static func fuel(_ value: Double, lng: LanguageManager.Language) -> String {
        let s = value == Double(Int(value))
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return s.replacingOccurrences(of: ".", with: AppStrings.decimalSeparator(lng))
    }

    /// Always-one-decimal variant (avg-consumption stat card).
    static func oneDecimal(_ value: Double, lng: LanguageManager.Language) -> String {
        let s = String(format: "%.1f", value)
        return s.replacingOccurrences(of: ".", with: AppStrings.decimalSeparator(lng))
    }

    /// Localized short volume unit ("л"/"L", "гал"/"gal") — carried over from
    /// the retired FuelSettingsCard so price units keep their RU spelling.
    static func volumeShort(_ rawUnit: String, lng: LanguageManager.Language) -> String {
        rawUnit == VolumeUnit.gallons.rawValue
            ? AppStrings.unitGallonsShort(lng)
            : AppStrings.unitLitresShort(lng)
    }

    static func distanceShort(_ rawUnit: String, lng: LanguageManager.Language) -> String {
        rawUnit == DistanceUnit.miles.rawValue
            ? AppStrings.unitMilesShort(lng)
            : AppStrings.km(lng)
    }

    /// Per-100 consumption unit («л/100км» / "gal/100mi") — the stored
    /// values are ALWAYS metric-style per-100 consumption; "mpg" would be
    /// both unconverted and inverse-scaled (higher = better), so the label
    /// must stay a per-100 unit regardless of the volume setting.
    static func consumptionUnit(volumeRaw: String, distanceRaw: String, lng: LanguageManager.Language) -> String {
        "\(volumeShort(volumeRaw, lng: lng))/100\(distanceShort(distanceRaw, lng: lng))"
    }
}
