import SwiftUI

/// «🚗 Honda Civic ▾» — the transport this trip is being recorded on, or
/// «Без транспорта» when it is being recorded on none.
///
/// One chip, two placements. The canon puts it top-left on every recording
/// screen; on Idle it lives inside the HUD card instead, where the person is
/// already looking when they decide to set off. What must NOT differ is the
/// chip itself, so both places build it from here.
///
/// It is shown even when the garage holds a single vehicle — without the «▾»,
/// since there is nothing to switch between, but still tappable: the sheet is
/// also the way into the Garage. Hiding it below two vehicles (the old rule)
/// meant most people never discovered that a trip has a vehicle at all.
struct VehicleChip: View {
    /// Recording uses the short name — «Civic» rather than «Honda Civic» —
    /// because the slot is shared with the GPS pill and the full name pushed
    /// into it.
    var compact = false
    var onTap: () -> Void

    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared

    /// Strictly what is selected — no «or the first vehicle» fallback.
    ///
    /// That fallback dates from when the app auto-created a vehicle and there
    /// was always one to fall back to. Now a garage can be empty, and «Без
    /// транспорта» is a deliberate choice rather than a missing one: with the
    /// fallback the chip named a vehicle the trip was not being stamped with
    /// (MapViewModel reads the persisted id and takes nil at face value), so
    /// the chip claimed one thing while the trip recorded another. Resolving
    /// through the shared helper keeps that rule in one place.
    private var activeVehicle: Vehicle? {
        settings.vehicle(for: settings.selectedVehicleId)
    }

    /// «▾» only when the sheet actually offers an alternative. One vehicle is
    /// enough, because «Без транспорта» is the other choice; an empty garage
    /// has no choice to make, though the chip stays tappable to reach the
    /// Garage.
    private var canSwitch: Bool { !settings.vehicles.isEmpty }

    /// «Honda Civic» → «Civic». The last word is the model, which is what
    /// people call the vehicle.
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
                    vehicleLabel(vehicle)
                } else {
                    noVehicleLabel
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

    @ViewBuilder
    private func vehicleLabel(_ vehicle: Vehicle) -> some View {
        if vehicle.isPixelAvatar {
            Image(vehicle.avatarEmoji)
                .resizable()
                // Nearest-neighbour: the pixel cars are drawn at asset
                // resolution and smoothing turns them to mush at 16pt.
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
    }

    /// Full opacity, same as a named vehicle: recording without transport is a
    /// first-class trip, and the greyed-out treatment this used to have read as
    /// «something is missing, go fix it». The glyph is neutral for the same
    /// reason — a crossed-out car is an error icon.
    @ViewBuilder
    private var noVehicleLabel: some View {
        Image(systemName: "minus.circle")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.75))
        Text(AppStrings.noVehicleOption(lang.language))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
    }
}
