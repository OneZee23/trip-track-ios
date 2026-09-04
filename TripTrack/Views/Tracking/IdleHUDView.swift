import SwiftUI

struct IdleHUDView: View {
    let totalKm: Double
    let tripCount: Int
    /// Geo-denied variant (Figma 475:119): title/subtitle swap and the slider
    /// opens Settings instead of starting a dead 0-km recording.
    var locationDenied: Bool = false
    /// No accepted GPS fix yet — the start control waits rather than starting
    /// a trip whose first minutes would be missing.
    var waitingForFix: Bool = false
    let onStartTrip: () -> Void
    var onBlockedStart: () -> Void = {}
    /// «Поеду пассажиром» — состояние БУДУЩЕЙ поездки, поэтому живёт во
    /// вью-модели, а не здесь: экран простоя пересоздаётся, намерение — нет.
    var isTransfer: Bool = false
    var onSetTransfer: (Bool) -> Void = { _ in }
    @EnvironmentObject private var lang: LanguageManager
    @ObservedObject private var settings = SettingsManager.shared
    @State private var showVehiclePicker = false

    private var activeVehicle: Vehicle? {
        settings.vehicle(for: settings.activeRecordableVehicleId)
    }

    /// «Я пассажир» одним тапом, прямо на экране, без шторки.
    ///
    /// Сначала это жило третьей строкой внутри шторки выбора машины — то есть
    /// за тапом по чипу, который выглядит как «выбрать машину». Догадаться,
    /// что сказать «я не за рулём» надо там же, невозможно: человек садится в
    /// такси и хочет нажать одну кнопку, а не искать её внутри выбора
    /// автомобиля. В шторке строка тоже осталась — для тех, кто уже там.
    private var passengerToggle: some View {
        Button {
            Haptics.selection()
            onSetTransfer(!isTransfer)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(AppStrings.passengerToggle(lang.language))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isTransfer ? .white : .white.opacity(0.7))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(isTransfer
                                       ? AppTheme.accent
                                       : Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(isTransfer ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("idle_passenger_toggle")
        .accessibilityAddTraits(isTransfer ? [.isSelected] : [])
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
                    .frame(width: 52, height: 32)
            }
            // Figma's card rhythm (574:129): ring at 22, then a steady 14 pt
            // between every block down to the slider, 22 pt under it.
            .padding(.top, 22)
            .padding(.bottom, 14)

            Text(locationDenied ? AppStrings.noGeoTitle(lang.language) : AppStrings.readyToRide(lang.language))
                .font(.inter(locationDenied ? 19 : 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(.bottom, 10)

            // The car this trip will be recorded on, one tap from the start
            // control. Shown with a single car in the garage too — the sheet
            // is also the door to «Управлять в Гараже», and hiding the chip
            // meant most people never learned a trip HAS a car.
            if !locationDenied {
                HStack(spacing: 8) {
                    // Приоритет у переключателя, а не у чипа: длинное имя
                    // машины («Mercedes-Benz E-Class») иначе съело бы строку
                    // целиком и вытолкнуло кнопку за край. Имя обрежется —
                    // кнопка обязана остаться целой.
                    VehicleChip(dimmed: isTransfer) { showVehiclePicker = true }
                    passengerToggle
                        .layoutPriority(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }

            if locationDenied {
                Text(AppStrings.noGeoSubtitle(lang.language))
                    .font(.inter(13))
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 24)
            } else if totalKm > 0 || tripCount > 0 {
                Text("\(formatKmWithSeparator(totalKm)) \(AppStrings.totalKm(lang.language)) · \(tripCount) \(AppStrings.tripsGenitive(lang.language, count: tripCount))")
                    .font(.inter(13).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
                    .padding(.bottom, 14)
            } else {
                Spacer().frame(height: 14)
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
                labelOverride: locationDenied ? AppStrings.openSettings(lang.language) : nil,
                // The geo-denied state has its own job for this control
                // (opening Settings), and it does not need a fix to do it.
                isBlocked: waitingForFix && !locationDenied,
                onBlockedAttempt: onBlockedStart
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
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
            VehiclePickerSheet(
                // Машины в архиве и проданные здесь не показываются: гараж
                // обещает, что запись идёт на активную, и шторка обязана
                // говорить ровно то же самое.
                checkedVehicleId: isTransfer ? .some(nil) : nil,
                onPick: { _ in onSetTransfer(false) },
                showsTransferOption: true,
                isTransferSelected: isTransfer,
                onPickTransfer: { onSetTransfer(true) }
            )
            .environmentObject(lang)
        }
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
        AppStrings.groupedNumber(Int(km.rounded()), lang.language)
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
