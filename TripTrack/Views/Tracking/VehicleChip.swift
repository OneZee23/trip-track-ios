import SwiftUI

/// «🚗 Honda Civic ▾» — the car this trip is being recorded on.
///
/// One chip, two placements. The canon puts it top-left on every recording
/// screen; on Idle it lives inside the HUD card instead, where the person is
/// already looking when they decide to set off. What must NOT differ is the
/// chip itself, so both places build it from here.
///
/// It is shown even when the garage holds a single car — without the «▾»,
/// since there is nothing to switch between, but still tappable: the sheet is
/// also the way into «＋ Управлять в Гараже». Hiding it below two cars (the
/// old rule) meant most people never discovered that a trip has a car at all.
struct VehicleChip: View {
    /// Recording uses the short name — «Civic» rather than «Honda Civic» —
    /// because the slot is shared with the GPS pill and the full name pushed
    /// into it.
    var compact = false
    var onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared

    private var activeVehicle: Vehicle? {
        settings.vehicles.first { $0.id == settings.selectedVehicleId }
            ?? settings.vehicles.first
    }

    private var canSwitch: Bool { settings.vehicles.count > 1 }

    /// «Honda Civic» → «Civic». The last word is the model, which is what
    /// people call the car.
    private var displayName: String? {
        guard let name = activeVehicle?.name else { return nil }
        guard compact, let model = name.split(separator: " ").last, name.count > 10 else {
            return name
        }
        return String(model)
    }

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 6) {
                if let vehicle = activeVehicle {
                    if vehicle.isPixelAvatar {
                        Image(vehicle.avatarEmoji)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    } else {
                        Text(vehicle.avatarEmoji).font(.system(size: 14))
                    }
                    Text(displayName ?? vehicle.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Image(systemName: "car")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(AppStrings.noVehicleShort(lang.language))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if canSwitch {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // Over the map (recording) the fill has to be dark, because the map
            // is not: a white-at-12% capsule with white text vanishes on a
            // daylight map, exactly as the old pause disc did. Dark glass also
            // matches the GPS pill sitting opposite it in the same row — they
            // are a pair and should read as one.
            //
            // Inside the Idle card the surface is already known and dark, so
            // the light capsule stays: dark-on-dark would disappear there.
            .background(Capsule().fill(compact
                                       ? Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.78)
                                       : Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(compact ? 0.14 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_chip")
    }
}
