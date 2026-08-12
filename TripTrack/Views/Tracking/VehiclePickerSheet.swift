import SwiftUI

/// Vehicle picker at record start (Figma 542:119): white bottom sheet with
/// one row per car, checkmark on the current selection, and a «Управлять в
/// Гараже» footer. Selection persists through SettingsManager so the
/// slide-to-start records against the picked car.
struct VehiclePickerSheet: View {
    /// Whether picking also makes this the app's current car.
    ///
    /// True where the pick is about what you are ABOUT to drive (the recording
    /// screen). False where it is about what you drove three weeks ago — the
    /// trip editor — because there the write-through silently changed which car
    /// the next recording would be stamped with.
    var persistsSelection: Bool = true
    /// Called with the picked car. The recording screen uses it to restamp the
    /// trip that is already running; the editor uses it to set the field.
    var onPick: ((UUID) -> Void)?

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        let c = AppTheme.colors(for: scheme)

        VStack(spacing: 0) {
            Capsule()
                .fill(.primary.opacity(0.18))
                .frame(width: 34, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 14)

            Text(AppStrings.vehiclePickerTitle(lang.language))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(c.text)
                .padding(.bottom, 16)

            // No ScrollView: the garage is capped at five cars, so the list
            // always fits — and a ScrollView is flexible, which means it
            // stretches to whatever height the sheet was given instead of
            // telling the sheet how tall it needs to be. Fixed content is what
            // makes the measurement below possible.
            VStack(spacing: Self.rowSpacing) {
                ForEach(settings.vehicles) { vehicle in
                    vehicleRow(vehicle, c: c)
                }
            }
            .padding(.horizontal, 16)

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Button {
                Haptics.tap()
                dismiss()
                // Garage lives under the Я tab — switch there; ProfileView
                // hosts the Garage entry point.
                NotificationCenter.default.post(name: .openGarage, object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    Text(AppStrings.manageInGarage(lang.language))
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 20)
        }
        // Measure what is actually in the sheet and make the sheet that tall.
        //
        // The height used to be arithmetic — a 160pt «chrome» constant that
        // included room for the home indicator, plus 62 per row. iOS 26 turned
        // sheets into cards that float inset from the screen edge and add that
        // room themselves, so the two stacked: the card came out taller than
        // the space it had and its bottom corners were cut off by the screen,
        // with a band of empty sheet above them. Measuring works on both,
        // because it asks the content instead of guessing for it.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SheetHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SheetHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
        .background(c.bg)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
    }

    /// Seeded with a plausible first-frame height so the sheet does not open at
    /// zero and animate open; the real measurement lands on the same frame.
    @State private var contentHeight: CGFloat = 260

    private struct SheetHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private static let rowSpacing: CGFloat = 4

    private func vehicleRow(_ vehicle: Vehicle, c: AppTheme.Colors) -> some View {
        let selected = vehicle.id == settings.selectedVehicleId
        return Button {
            Haptics.selection()
            // Persist the pick — a bare `selectedVehicleId =` would not write
            // through to CoreData, so slide-to-start (which re-reads from the
            // settings entity) would record against the previous car.
            if persistsSelection {
                settings.selectVehicle(id: vehicle.id)
            }
            onPick?(vehicle.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(c.cardAlt)
                        .frame(width: 42, height: 42)
                    if vehicle.isPixelAvatar {
                        Image(vehicle.avatarEmoji)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                    } else {
                        Text(vehicle.avatarEmoji).font(.system(size: 20))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.text)
                        .lineLimit(1)
                    Text("\(Int(vehicle.odometerKm)) \(AppStrings.km(lang.language))")
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(selected ? AppTheme.accent.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? AppTheme.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
