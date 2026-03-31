import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showAddVehicle = false
    @State private var newName = ""
    @State private var newEmoji = "🚗"
    @State private var renameVehicleId: UUID?
    @State private var renameText = ""

    private let vehicleEmojis = ["🏎️", "🚗", "🏍️", "🚙", "🛻", "🚐", "🏁", "⛽"]

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 1. All vehicles list (top)
                    VStack(alignment: .leading, spacing: 0) {
                        if settings.vehicles.isEmpty {
                            emptyState(c: c, isRu: isRu)
                        } else {
                            ForEach(Array(settings.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                                vehicleRow(vehicle: vehicle, c: c, isRu: isRu)

                                if index < settings.vehicles.count - 1 {
                                    Rectangle().fill(c.border).frame(height: 1).padding(.leading, 60)
                                }
                            }
                        }

                        Spacer().frame(height: 8)
                    }
                    .surfaceCard(cornerRadius: 16)

                    // Add vehicle button
                    Button { showAddVehicle = true } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(AppTheme.accent)
                            Text(isRu ? "Добавить автомобиль" : "Add vehicle")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(c.text)
                            Spacer()
                        }
                        .padding(16)
                        .surfaceCard(cornerRadius: 16)
                    }
                    .buttonStyle(.plain)

                    // 2. Fuel settings for active vehicle
                    if let active = activeVehicle {
                        FuelSettingsCard(
                            vehicleId: active.id,
                            initialCity: active.cityConsumption,
                            initialHighway: active.highwayConsumption,
                            initialPrice: active.fuelPrice,
                            isRu: isRu,
                            settings: settings
                        )
                        .id(active.id)
                    }

                    // 3. Units settings
                    UnitsSettingsCard()
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(c.bg)
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationTitle(isRu ? "Гараж" : "Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                    }
                }
            }
            .toolbarBackground(c.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAddVehicle) {
                addVehicleSheet(c: c, isRu: isRu)
            }
            .alert(
                isRu ? "Переименовать" : "Rename",
                isPresented: Binding(
                    get: { renameVehicleId != nil },
                    set: { if !$0 { renameVehicleId = nil } }
                )
            ) {
                TextField(isRu ? "Название" : "Name", text: $renameText)
                Button(isRu ? "Сохранить" : "Save") {
                    if let id = renameVehicleId {
                        settings.renameVehicle(id: id, name: renameText.trimmingCharacters(in: .whitespaces))
                    }
                    renameVehicleId = nil
                }
                Button(isRu ? "Отмена" : "Cancel", role: .cancel) {
                    renameVehicleId = nil
                }
            }
        }
    }

    private var activeVehicle: Vehicle? {
        if let id = settings.selectedVehicleId {
            return settings.vehicles.first { $0.id == id }
        }
        return settings.vehicles.first
    }


    // MARK: - Vehicle Row

    private func vehicleRow(vehicle: Vehicle, c: AppTheme.Colors, isRu: Bool) -> some View {
        let isActive = vehicle.id == (settings.selectedVehicleId ?? settings.vehicles.first?.id)

        return Button {
            Haptics.tap()
            settings.selectedVehicleId = vehicle.id
            settings.saveSettings()
        } label: {
            HStack(spacing: 12) {
                // Emoji
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isActive ? AppTheme.accentBg : c.cardAlt)
                        .frame(width: 44, height: 44)
                    vehicle.avatarView(size: 36)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vehicle.name.isEmpty ? (isRu ? "Без имени" : "Unnamed") : vehicle.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(c.text)
                            .lineLimit(1)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("LVL \(vehicle.level)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(c.textSecondary)
                        Text("·")
                            .foregroundStyle(c.textTertiary)
                        Text(String(format: "%.0f km", vehicle.odometerKm))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                    }
                }

                Spacer()

                // Stickers count
                if !vehicle.stickers.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(vehicle.stickers.prefix(3), id: \.self) { sticker in
                            Image(systemName: sticker.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(sticker.color)
                        }
                        if vehicle.stickers.count > 3 {
                            Text("+\(vehicle.stickers.count - 3)")
                                .font(.system(size: 9))
                                .foregroundStyle(c.textTertiary)
                        }
                    }
                }

                // Edit menu
                Menu {
                    Button {
                        renameText = vehicle.name
                        renameVehicleId = vehicle.id
                    } label: {
                        Label(isRu ? "Переименовать" : "Rename", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        settings.deleteVehicle(id: vehicle.id)
                        if settings.selectedVehicleId == vehicle.id {
                            settings.selectedVehicleId = settings.vehicles.first?.id
                            settings.saveSettings()
                        }
                    } label: {
                        Label(isRu ? "Удалить" : "Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    // MARK: - Fuel Settings (no-op, handled by FuelSettingsCard)

    private func emptyState(c: AppTheme.Colors, isRu: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "car.fill")
                .font(.system(size: 28))
                .foregroundStyle(c.textTertiary)
            Text(isRu ? "Добавьте ваш автомобиль" : "Add your vehicle")
                .font(.system(size: 14))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Add Vehicle Sheet

    private func addVehicleSheet(c: AppTheme.Colors, isRu: Bool) -> some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Emoji selector
                Text(newEmoji)
                    .font(.system(size: 56))
                    .frame(width: 88, height: 88)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 20))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(vehicleEmojis, id: \.self) { emoji in
                        Button {
                            Haptics.tap()
                            newEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(newEmoji == emoji ? AppTheme.accentBg : c.cardAlt)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(newEmoji == emoji ? AppTheme.accent : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)

                // Name input
                TextField(isRu ? "Название авто" : "Vehicle name", text: $newName)
                    .font(.system(size: 18, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(14)
                    .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 32)

                Spacer()

                // Add button
                Button {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    settings.addVehicle(name: name, emoji: newEmoji)
                    // Select the new vehicle
                    if let newVehicle = settings.vehicles.last {
                        settings.selectedVehicleId = newVehicle.id
                        settings.saveSettings()
                    }
                    newName = ""
                    newEmoji = "🚗"
                    showAddVehicle = false
                } label: {
                    Text(isRu ? "Добавить" : "Add")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            newName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.gray
                                : AppTheme.accent,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
            .padding(.top, 24)
            .background(c.bg)
            .navigationTitle(isRu ? "Новый автомобиль" : "New vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showAddVehicle = false } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Isolated Fuel Settings Card

/// Zero-dependency fuel card. Uses AppStorage for units (lightweight, no re-render chain).
private struct FuelSettingsCard: View {
    let vehicleId: UUID
    let initialCity: Double
    let initialHighway: Double
    let initialPrice: Double
    let isRu: Bool
    let settings: SettingsManager

    @State private var city: String = ""
    @State private var highway: String = ""
    @State private var price: String = ""
    @State private var dirty = false
    @State private var didLoad = false
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("fuelCurrency") private var currency: String = "₽"

    private var volShort: String {
        volumeUnit == "gallons" ? (isRu ? "гал" : "gal") : (isRu ? "л" : "L")
    }
    private var distShort: String {
        distanceUnit == "miles" ? (isRu ? "миль" : "mi") : (isRu ? "км" : "km")
    }
    private var consumptionLabel: String {
        "\(volShort)/100\(distShort)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.accent)
                Text(isRu ? "Расход топлива" : "Fuel consumption")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                    save()
                    dirty = false
                } label: {
                    Text(isRu ? "Сохранить" : "Save")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(AppTheme.accent, in: Capsule())
                }
                .opacity(dirty ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: dirty)
            }

            HStack(spacing: 8) {
                fuelInput(
                    label: isRu ? "Город" : "City",
                    unit: consumptionLabel,
                    text: $city,
                    placeholder: "10",
                    maxValue: 50
                )
                fuelInput(
                    label: isRu ? "Трасса" : "Highway",
                    unit: consumptionLabel,
                    text: $highway,
                    placeholder: "6",
                    maxValue: 50
                )
                fuelInput(
                    label: isRu ? "Цена" : "Price",
                    unit: "\(currency)/\(volShort)",
                    text: $price,
                    placeholder: "56",
                    maxValue: 999
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            city = fmt(initialCity)
            highway = fmt(initialHighway)
            price = fmt(initialPrice)
        }
    }

    private func fuelInput(label: String, unit: String, text: Binding<String>, placeholder: String, maxValue: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            TextField(placeholder, text: Binding(
                get: { text.wrappedValue },
                set: { newValue in
                    // Allow only digits, dots, and commas
                    let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "," }
                    // Parse and clamp
                    let normalized = filtered.replacingOccurrences(of: ",", with: ".")
                    if let val = Double(normalized), val > maxValue {
                        text.wrappedValue = fmt(maxValue)
                    } else {
                        text.wrappedValue = filtered
                    }
                    dirty = true
                }
            ))
            .keyboardType(.decimalPad)
            .font(.system(size: 15))
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
            Text(unit)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func save() {
        let c = Double(city.replacingOccurrences(of: ",", with: ".")) ?? initialCity
        let h = Double(highway.replacingOccurrences(of: ",", with: ".")) ?? initialHighway
        let p = Double(price.replacingOccurrences(of: ",", with: ".")) ?? initialPrice
        settings.updateVehicleFuel(id: vehicleId, city: c, highway: h, price: p)
    }

    private func fmt(_ v: Double) -> String {
        let s = v == Double(Int(v)) ? String(format: "%.0f", v) : String(format: "%.1f", v)
        return isRu ? s.replacingOccurrences(of: ".", with: ",") : s
    }
}

// MARK: - Units Settings Card

private struct UnitsSettingsCard: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("fuelCurrency") private var currency: String = "₽"

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let isRu = lang.language == .ru

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "ruler.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.blue)
                Text(isRu ? "Единицы измерения" : "Units")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.text)
            }

            // Distance
            unitRow(
                label: isRu ? "Расстояние" : "Distance",
                options: DistanceUnit.allCases.map { ($0.rawValue, isRu ? $0.labelFull.ru : $0.labelFull.en) },
                selected: $distanceUnit,
                c: c
            )

            // Volume
            unitRow(
                label: isRu ? "Объём" : "Volume",
                options: VolumeUnit.allCases.map { ($0.rawValue, isRu ? $0.labelFull.ru : $0.labelFull.en) },
                selected: $volumeUnit,
                c: c
            )

            // Currency
            VStack(alignment: .leading, spacing: 6) {
                Text(isRu ? "Валюта" : "Currency")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FuelCurrency.allCases, id: \.self) { cur in
                            Button {
                                Haptics.tap()
                                currency = cur.symbol
                            } label: {
                                Text(cur.symbol)
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 40, height: 36)
                                    .foregroundStyle(currency == cur.symbol ? .white : c.textSecondary)
                                    .background(
                                        currency == cur.symbol ? AppTheme.accent : c.cardAlt,
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(16)
        .surfaceCard(cornerRadius: 16)
    }

    private func unitRow(label: String, options: [(value: String, label: String)], selected: Binding<String>, c: AppTheme.Colors) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)

            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    Button {
                        Haptics.tap()
                        selected.wrappedValue = option.value
                    } label: {
                        Text(option.label)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundStyle(selected.wrappedValue == option.value ? .white : c.textSecondary)
                            .background(
                                selected.wrappedValue == option.value ? AppTheme.accent : c.cardAlt,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
