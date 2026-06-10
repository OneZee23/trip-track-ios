import SwiftUI

struct IdleHUDView: View {
    let totalKm: Double
    let tripCount: Int
    let onStartTrip: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared

    private var activeVehicle: Vehicle? {
        settings.vehicles.first { $0.id == settings.selectedVehicleId }
            ?? settings.vehicles.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pulsing accent ring with pixel car
            ZStack {
                // Outer pulsing glow
                Circle()
                    .stroke(AppTheme.accent.opacity(0.2), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .modifier(PulseRingModifier())

                // Main ring
                Circle()
                    .stroke(AppTheme.accent.opacity(0.7), lineWidth: 2.5)
                    .frame(width: 82, height: 82)

                // Orange glow fill
                Circle()
                    .fill(AppTheme.accent.opacity(0.2))
                    .frame(width: 82, height: 82)

                Image("PixelCar")
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)
            }
            .padding(.top, 32)
            .padding(.bottom, 20)

            Text(AppStrings.readyToRide(lang.language))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 6)

            // Quick vehicle picker — multi-car users were skipping the
            // start because flipping vehicles meant a trip into Profile →
            // Garage. Tap-to-switch right here removes that friction; the
            // chip is hidden when only one vehicle exists.
            if settings.vehicles.count > 1 {
                vehicleChip
                    .padding(.bottom, 10)
            }

            if totalKm > 0 || tripCount > 0 {
                Text("\(formatKmWithSeparator(totalKm)) \(AppStrings.totalKm(lang.language)) · \(tripCount) \(AppStrings.trips(lang.language))")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 28)
            } else {
                Spacer().frame(height: 20)
            }

            // Slide to start
            SlideToStartView(onStartTrip: onStartTrip)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0.08, green: 0.08, blue: 0.09).opacity(0.75))
                )
        )
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var vehicleChip: some View {
        Menu {
            ForEach(settings.vehicles) { vehicle in
                Button {
                    Haptics.selection()
                    // Persist the pick — a bare `selectedVehicleId =` would not
                    // write through to CoreData, so the slide-to-start (which
                    // re-reads from the settings entity) would record the trip
                    // against the previously-saved car.
                    settings.selectVehicle(id: vehicle.id)
                } label: {
                    if vehicle.id == settings.selectedVehicleId {
                        Label(vehicle.name, systemImage: "checkmark")
                    } else {
                        Text(vehicle.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let v = activeVehicle {
                    if v.isPixelAvatar {
                        Image(v.avatarEmoji)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                    } else {
                        Text(v.avatarEmoji).font(.system(size: 14))
                    }
                    Text(v.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Image(systemName: "car")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(lang.language == .ru ? "Без авто" : "No vehicle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.12)))
        }
    }

    private static let kmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    private func formatKmWithSeparator(_ km: Double) -> String {
        Self.kmFormatter.string(from: NSNumber(value: km)) ?? "\(Int(km))"
    }

}

// MARK: - Quick Stat Card

private struct QuickStatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .surfaceCard(cornerRadius: 14)
    }
}

// MARK: - Pulse Ring Animation

private struct PulseRingModifier: ViewModifier {
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(animate ? 1.1 : 1.0)
            .opacity(animate ? 0 : 0.5)
            .onAppear {
                withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}
