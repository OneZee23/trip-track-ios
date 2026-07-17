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

/// 6pt capsule progress bar with a gradient fill, fed by `progressToNextLevel`.
struct VehicleXPBar: View {
    let progress: Double
    let tint: Color

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(c.cardAlt)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Section Label

/// Uppercased tracking section label («СТИКЕРЫ», «РАСХОД ТОПЛИВА», …).
struct GarageSectionLabel: View {
    let text: String
    var color: Color?

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color ?? c.textTertiary)
    }
}

// MARK: - Shared Garage formatting

enum GarageFormat {
    private static let odometerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// "38 420" — odometer value with space thousands grouping.
    static func odometer(_ km: Double) -> String {
        odometerFormatter.string(from: NSNumber(value: km.rounded()))
            ?? String(format: "%.0f", km)
    }

    /// Retired FuelSettingsCard's proven display format: integral values drop
    /// the fraction, others keep one decimal; RU uses a decimal comma.
    static func fuel(_ value: Double, isRu: Bool) -> String {
        let s = value == Double(Int(value))
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
        return isRu ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// Always-one-decimal variant (avg-consumption stat card).
    static func oneDecimal(_ value: Double, isRu: Bool) -> String {
        let s = String(format: "%.1f", value)
        return isRu ? s.replacingOccurrences(of: ".", with: ",") : s
    }

    /// Localized short volume unit ("л"/"L", "гал"/"gal") — carried over from
    /// the retired FuelSettingsCard so price units keep their RU spelling.
    static func volumeShort(_ rawUnit: String, isRu: Bool) -> String {
        rawUnit == VolumeUnit.gallons.rawValue
            ? (isRu ? "гал" : "gal")
            : (isRu ? "л" : "L")
    }

    static func distanceShort(_ rawUnit: String, isRu: Bool) -> String {
        rawUnit == DistanceUnit.miles.rawValue
            ? (isRu ? "миль" : "mi")
            : (isRu ? "км" : "km")
    }

    /// Per-100 consumption unit («л/100км» / "gal/100mi") — the stored
    /// values are ALWAYS metric-style per-100 consumption; "mpg" would be
    /// both unconverted and inverse-scaled (higher = better), so the label
    /// must stay a per-100 unit regardless of the volume setting.
    static func consumptionUnit(volumeRaw: String, distanceRaw: String, isRu: Bool) -> String {
        "\(volumeShort(volumeRaw, isRu: isRu))/100\(distanceShort(distanceRaw, isRu: isRu))"
    }
}
