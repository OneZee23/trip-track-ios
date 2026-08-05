import SwiftUI

struct IdleHUDView: View {
    let totalKm: Double
    let tripCount: Int
    /// Geo-denied variant (Figma 475:119): title/subtitle swap and the slider
    /// opens Settings instead of starting a dead 0-km recording.
    var locationDenied: Bool = false
    let onStartTrip: () -> Void
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showVehiclePicker = false

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
            .padding(.top, 28)
            .padding(.bottom, 16)

            Text(locationDenied ? AppStrings.noGeoTitle(lang.language) : AppStrings.readyToRide(lang.language))
                .font(.system(size: locationDenied ? 19 : 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 6)

            // Quick vehicle picker — multi-car users were skipping the
            // start because flipping vehicles meant a trip into Profile →
            // Garage. The chip opens the 6.1.0 picker sheet (Figma 542:119);
            // hidden when only one vehicle exists.
            if !locationDenied && settings.vehicles.count > 1 {
                vehicleChip
                    .padding(.bottom, 10)
            }

            if locationDenied {
                Text(AppStrings.noGeoSubtitle(lang.language))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 24)
            } else if totalKm > 0 || tripCount > 0 {
                Text("\(formatKmWithSeparator(totalKm)) \(AppStrings.totalKm(lang.language)) · \(tripCount) \(AppStrings.tripsGenitive(lang.language, count: tripCount))")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 24)
            } else {
                Spacer().frame(height: 20)
            }

            SlideToStartView(
                onStartTrip: {
                    if locationDenied {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        onStartTrip()
                    }
                },
                labelOverride: locationDenied ? AppStrings.openSettings(lang.language) : nil
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color(red: 40/255, green: 40/255, blue: 42/255).opacity(0.72))
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        )
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .sheet(isPresented: $showVehiclePicker) {
            VehiclePickerSheet()
                .environmentObject(lang)
        }
    }

    @ViewBuilder
    private var vehicleChip: some View {
        Button {
            Haptics.tap()
            showVehiclePicker = true
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
                    Text(AppStrings.noVehicleShort(lang.language))
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
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_chip")
    }

    // Per-language grouping, consistent with My Map (MyMapView.groupedNumber):
    // RU «2 430» (Figma «2 430 км всего»), EN "2,430".
    private static let ruKmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = " "
        return f
    }()

    private static let enKmFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    private func formatKmWithSeparator(_ km: Double) -> String {
        let formatter = lang.language == .ru ? Self.ruKmFormatter : Self.enKmFormatter
        return formatter.string(from: NSNumber(value: km)) ?? "\(Int(km))"
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
