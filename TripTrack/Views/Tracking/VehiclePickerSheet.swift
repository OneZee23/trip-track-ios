import SwiftUI

/// Vehicle picker at record start (Figma 542:119): white bottom sheet with
/// one row per car, checkmark on the current selection, and a «Управлять в
/// Гараже» footer. Selection persists through SettingsManager so the
/// slide-to-start records against the picked car.
struct VehiclePickerSheet: View {
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

            // Scrolls when the garage outgrows the medium detent (5+ cars).
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(settings.vehicles) { vehicle in
                        vehicleRow(vehicle, c: c)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollBounceBehavior(.basedOnSize)

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

            Spacer(minLength: 0)
        }
        .background(c.bg)
        .presentationDetents([.medium])
        .presentationCornerRadius(22)
        .presentationDragIndicator(.hidden)
    }

    private func vehicleRow(_ vehicle: Vehicle, c: AppTheme.Colors) -> some View {
        let selected = vehicle.id == settings.selectedVehicleId
        return Button {
            Haptics.selection()
            // Persist the pick — a bare `selectedVehicleId =` would not write
            // through to CoreData, so slide-to-start (which re-reads from the
            // settings entity) would record against the previous car.
            settings.selectVehicle(id: vehicle.id)
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
