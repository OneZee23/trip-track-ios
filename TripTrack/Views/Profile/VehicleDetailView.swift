import SwiftUI

struct VehicleDetailView: View {
    let vehicleId: UUID
    @ObservedObject private var settings = SettingsManager.shared
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isNameFocused: Bool


    private var vehicle: Vehicle? {
        settings.vehicles.first { $0.id == vehicleId }
    }

    var body: some View {
        guard let vehicle else {
            return AnyView(EmptyView())
        }
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru
        let frame = frameColor(for: vehicle)

        return AnyView(
            NavigationStack {
                ScrollView {
                    VStack(spacing: 12) {
                        headerSection(vehicle: vehicle, c: c, isRu: isRu, frame: frame)
                        odometerCard(vehicle: vehicle, c: c, isRu: isRu, frame: frame)
                        stickersCard(vehicle: vehicle, c: c, isRu: isRu)
                        avatarCard(vehicle: vehicle, c: c, frame: frame)

                        FuelSettingsCard(
                            vehicleId: vehicle.id,
                            initialCity: vehicle.cityConsumption,
                            initialHighway: vehicle.highwayConsumption,
                            initialPrice: vehicle.fuelPrice,
                            isRu: isRu,
                            settings: settings
                        )
                        .id(vehicle.id)

                        UnitsSettingsCard()

                        createdFooter(vehicle: vehicle, c: c, isRu: isRu)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(c.bg)
                .navigationTitle(isRu ? "Мой автомобиль" : "My Vehicle")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(c.textSecondary)
                                .frame(width: 30, height: 30)
                                .background(c.cardAlt, in: Circle())
                        }
                    }
                }
            }
        )
    }

    // MARK: - Header

    private func headerSection(vehicle: Vehicle, c: AppTheme.Colors, isRu: Bool, frame: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(frame.opacity(0.15))
                    .frame(width: 96, height: 96)
                Circle()
                    .strokeBorder(frame.opacity(0.3), lineWidth: 2)
                    .frame(width: 96, height: 96)
                vehicle.avatarView(size: 56)
            }

            if isEditingName {
                TextField(isRu ? "Имя машины" : "Vehicle name", text: $editedName)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit { saveName() }
                    .onAppear { isNameFocused = true }
            } else {
                Button {
                    editedName = vehicle.name
                    isEditingName = true
                } label: {
                    HStack(spacing: 6) {
                        Text(vehicle.name.isEmpty ? (isRu ? "Мой авто" : "My car") : vehicle.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(c.text)
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundStyle(c.textTertiary)
                    }
                }
            }

            Text("LVL \(vehicle.level) · \(vehicle.levelTitle(lang.language))")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(frame)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Odometer

    private func odometerCard(vehicle: Vehicle, c: AppTheme.Colors, isRu: Bool, frame: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(isRu ? "ПРОБЕГ" : "ODOMETER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(c.textSecondary)
                    .tracking(0.5)
                Spacer()
                Text(formatOdometer(vehicle.odometerKm))
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(c.cardAlt).frame(height: 8)
                    Capsule()
                        .fill(frame)
                        .frame(width: max(4, geo.size.width * vehicle.progressToNextLevel), height: 8)
                }
            }
            .frame(height: 8)

            if let nextKm = vehicle.kmToNextLevel {
                Text(isRu ? "До следующего уровня: \(String(format: "%.0f", nextKm)) км"
                     : "Next level in: \(String(format: "%.0f", nextKm)) km")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            } else {
                Text(isRu ? "Максимальный уровень достигнут!" : "Maximum level reached!")
                    .font(.system(size: 12))
                    .foregroundStyle(frame)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Stickers

    private func stickersCard(vehicle: Vehicle, c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isRu ? "СТИКЕРЫ" : "STICKERS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .tracking(0.5)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 10) {
                ForEach(VehicleSticker.allCases, id: \.self) { sticker in
                    let earned = vehicle.stickers.contains(sticker)
                    VStack(spacing: 4) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(earned ? sticker.color.opacity(0.12) : c.cardAlt)
                                .frame(width: 44, height: 44)
                            if earned {
                                Image(systemName: sticker.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(sticker.color)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(c.textTertiary.opacity(0.5))
                            }
                        }
                        Text(isRu ? sticker.titleRu() : sticker.titleEn())
                            .font(.system(size: 9))
                            .foregroundStyle(earned ? c.text : c.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Avatar Selector

    private func avatarCard(vehicle: Vehicle, c: AppTheme.Colors, frame: Color) -> some View {
        let isRu = lang.language == .ru
        return VStack(alignment: .leading, spacing: 10) {
            Text(isRu ? "АВАТАР" : "AVATAR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(c.textSecondary)
                .tracking(0.5)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                // Pixel cars
                ForEach(Vehicle.pixelCarAssets, id: \.self) { asset in
                    avatarOption(
                        content: AnyView(
                            Image(asset).resizable().scaledToFit().frame(width: 32, height: 32)
                        ),
                        isSelected: vehicle.avatarEmoji == asset,
                        frame: frame,
                        c: c
                    ) {
                        settings.updateVehicleAvatar(id: vehicleId, emoji: asset)
                    }
                }
                // Emoji avatars
                ForEach(Vehicle.defaultAvatars, id: \.self) { emoji in
                    avatarOption(
                        content: AnyView(
                            Text(emoji).font(.system(size: 28))
                        ),
                        isSelected: vehicle.avatarEmoji == emoji,
                        frame: frame,
                        c: c
                    ) {
                        settings.updateVehicleAvatar(id: vehicleId, emoji: emoji)
                    }
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func avatarOption(content: AnyView, isSelected: Bool, frame: Color, c: AppTheme.Colors, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? frame.opacity(0.12) : c.cardAlt)
                    .frame(height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? frame : .clear, lineWidth: 2)
                    )
                content
            }
        }
        .buttonStyle(.plain)
    }


    // MARK: - Footer

    private func createdFooter(vehicle: Vehicle, c: AppTheme.Colors, isRu: Bool) -> some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: isRu ? "ru_RU" : "en_US")
        let dateStr = formatter.string(from: vehicle.createdAt)

        return Text(isRu ? "С вами с \(dateStr)" : "With you since \(dateStr)")
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    // MARK: - Actions

    private func saveName() {
        let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            settings.renameVehicle(id: vehicleId, name: trimmed)
        }
        isEditingName = false
    }

    // MARK: - Helpers

    private func frameColor(for vehicle: Vehicle) -> Color {
        switch vehicle.level {
        case 1...2: return .gray
        case 3: return Color(red: 205/255, green: 127/255, blue: 50/255)
        case 4...5: return Color(red: 192/255, green: 192/255, blue: 192/255)
        case 6: return Color(red: 255/255, green: 215/255, blue: 0/255)
        case 7...8: return Color(red: 180/255, green: 210/255, blue: 230/255)
        default: return AppTheme.accent
        }
    }

    private func formatOdometer(_ km: Double) -> String {
        if km >= 1000 {
            return String(format: "%.1fK km", km / 1000)
        }
        return String(format: "%.0f km", km)
    }

}
