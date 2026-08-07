import SwiftUI

/// Shared add/edit vehicle form (Figma 500:129 add / 541:119 edit).
/// Presented as a sheet from the garage «+» (add) and from the vehicle
/// detail menu and fuel rows (edit).
struct VehicleEditFormView: View {
    enum Mode {
        case add
        case edit(UUID)
    }

    let mode: Mode

    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var name: String
    /// nil = user hasn't picked a cell and the vehicle has a pixel avatar —
    /// saving then must NOT clobber the pixel avatar (deferred integration
    /// point for the car-avatar system).
    @State private var selectedAvatar: String?
    @State private var city: String
    @State private var highway: String
    @State private var price: String
    /// Initial DISPLAY strings — fuel writes fire only when the text
    /// actually changed. Comparing parsed(display) against the stored
    /// full-precision doubles silently rounded e.g. 9.15 → 9.2 on a
    /// name-only save (and enqueued a spurious sync op).
    @State private var initialCity: String
    @State private var initialHighway: String
    @State private var initialPrice: String

    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage(FuelCurrency.storageKey) private var currency: String = FuelCurrency.defaultSymbol

    /// Snapshot of the edited vehicle taken at init — used for
    /// changed-only saves so SyncEnqueuer isn't churned needlessly.
    private let editedVehicle: Vehicle?

    init(mode: Mode) {
        self.mode = mode
        let isRu = LanguageManager.currentLanguage == .ru

        if case .edit(let id) = mode,
           let vehicle = SettingsManager.shared.vehicles.first(where: { $0.id == id }) {
            editedVehicle = vehicle
            _name = State(initialValue: vehicle.name)
            _selectedAvatar = State(initialValue: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji)
            _city = State(initialValue: GarageFormat.fuel(vehicle.cityConsumption, isRu: isRu))
            _highway = State(initialValue: GarageFormat.fuel(vehicle.highwayConsumption, isRu: isRu))
            _price = State(initialValue: GarageFormat.fuel(vehicle.fuelPrice, isRu: isRu))
        } else {
            editedVehicle = nil
            let defaults = Vehicle()
            _name = State(initialValue: "")
            // Figma 500:129 draws the FIRST grid cell selected by default.
            _selectedAvatar = State(initialValue: Vehicle.defaultAvatars.first ?? "🚗")
            _city = State(initialValue: GarageFormat.fuel(defaults.cityConsumption, isRu: isRu))
            _highway = State(initialValue: GarageFormat.fuel(defaults.highwayConsumption, isRu: isRu))
            _price = State(initialValue: GarageFormat.fuel(defaults.fuelPrice, isRu: isRu))
        }
        _initialCity = State(initialValue: _city.wrappedValue)
        _initialHighway = State(initialValue: _highway.wrappedValue)
        _initialPrice = State(initialValue: _price.wrappedValue)
    }

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        VStack(spacing: 0) {
            navRow(c: c, l: l)
            ScrollView {
                VStack(spacing: 12) {
                    nameCard(c: c, l: l)
                    avatarCard(c: c, l: l)
                    fuelCard(c: c, l: l)
                    priceCard(c: c, l: l)
                    if let vehicle = editedVehicle {
                        mileageCard(vehicle, c: c, l: l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(c.bg)
        .safeAreaInset(edge: .bottom) {
            saveButton(l: l)
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Nav Row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ZStack {
            Text(title(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    NavCircleIcon(systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vehicle_form_close")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func title(_ l: LanguageManager.Language) -> String {
        switch mode {
        case .add: return AppStrings.addVehicleTitle(l)
        case .edit: return AppStrings.myVehicle(l)
        }
    }

    // MARK: - Name

    private func nameCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.vehicleNameSection(l), color: c.textSecondary)
            TextField(AppStrings.vehicleNamePlaceholder(l), text: $name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Avatar

    private func avatarCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.avatarSection(l), color: c.textSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(Vehicle.defaultAvatars, id: \.self) { emoji in
                    avatarCell(emoji, c: c)
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func avatarCell(_ emoji: String, c: AppTheme.Colors) -> some View {
        let isSelected = selectedAvatar == emoji
        return Button {
            Haptics.tap()
            selectedAvatar = emoji
        } label: {
            Text(emoji)
                .font(.system(size: 26))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AppTheme.accent.opacity(0.12) : c.cardAlt)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fuel

    private func fuelCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.fuelSectionLabel(l), color: c.textSecondary)
            fuelInputRow(label: AppStrings.fuelCity(l), text: $city, unit: consumptionUnitLabel(l), maxValue: 50, c: c)
            fuelInputRow(label: AppStrings.fuelHighway(l), text: $highway, unit: consumptionUnitLabel(l), maxValue: 50, c: c)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func priceCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Figma 500:129/541:119: the form pill shows the bare currency
        // symbol; the per-volume unit belongs to the DETAIL fuel row only.
        let priceUnit = currency
        return VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.fuelPriceRow(l), color: c.textSecondary)
            fuelInputRow(label: AppStrings.pricePerLiter(l), text: $price, unit: priceUnit, maxValue: 999, c: c)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    /// Pill-styled inline decimal input. Input filtering, RU comma
    /// normalization and clamping are the retired FuelSettingsCard's
    /// proven logic, verbatim.
    private func fuelInputRow(label: String, text: Binding<String>, unit: String, maxValue: Double, c: AppTheme.Colors) -> some View {
        let isRu = lang.language == .ru
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                TextField("0", text: Binding(
                    get: { text.wrappedValue },
                    set: { newValue in
                        // Allow only digits, dots, and commas
                        let filtered = newValue.filter { $0.isNumber || $0 == "." || $0 == "," }
                        // Parse and clamp
                        let normalized = filtered.replacingOccurrences(of: ",", with: ".")
                        if let val = Double(normalized), val > maxValue {
                            text.wrappedValue = GarageFormat.fuel(maxValue, isRu: isRu)
                        } else {
                            text.wrappedValue = filtered
                        }
                    }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .frame(width: 64)

                Text(unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Mileage (edit only, read-only)

    private func mileageCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GarageSectionLabel(text: AppStrings.mileageSection(l), color: c.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(GarageFormat.odometer(vehicle.odometerKm))
                    .font(.system(size: 22, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
                Text(AppStrings.km(l))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
            Text(AppStrings.mileageAutoHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Save

    private func saveButton(l: LanguageManager.Language) -> some View {
        let trimmedEmpty = name.trimmingCharacters(in: .whitespaces).isEmpty
        return Button {
            save()
        } label: {
            Text(AppStrings.save(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(trimmedEmpty ? Color.gray : AppTheme.accent, in: Capsule())
        }
        .disabled(trimmedEmpty)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        switch mode {
        case .add:
            settings.addVehicle(name: trimmed, emoji: selectedAvatar ?? "🚗")
            // The vehicles reload is name-sorted, so `vehicles.last` picks the
            // wrong car when the new name doesn't sort last — select the newest
            // vehicle by creation date instead.
            guard let newVehicle = settings.vehicles.max(by: { $0.createdAt < $1.createdAt }) else { break }
            let defaults = Vehicle()
            let cityVal = parsed(city) ?? defaults.cityConsumption
            let highwayVal = parsed(highway) ?? defaults.highwayConsumption
            let priceVal = parsed(price) ?? defaults.fuelPrice
            if cityVal != defaults.cityConsumption
                || highwayVal != defaults.highwayConsumption
                || priceVal != defaults.fuelPrice {
                settings.updateVehicleFuel(id: newVehicle.id, city: cityVal, highway: highwayVal, price: priceVal)
            }
            settings.selectVehicle(id: newVehicle.id)

        case .edit(let id):
            guard let original = editedVehicle else { break }
            if trimmed != original.name {
                settings.renameVehicle(id: id, name: trimmed)
            }
            // Avatar is written only when the user explicitly picked a cell —
            // protects pixel_car_* avatars from being clobbered.
            if let avatar = selectedAvatar, avatar != original.avatarEmoji {
                settings.updateVehicleAvatar(id: id, emoji: avatar)
            }
            if city != initialCity || highway != initialHighway || price != initialPrice {
                settings.updateVehicleFuel(
                    id: id,
                    city: city != initialCity ? (parsed(city) ?? original.cityConsumption) : original.cityConsumption,
                    highway: highway != initialHighway ? (parsed(highway) ?? original.highwayConsumption) : original.highwayConsumption,
                    price: price != initialPrice ? (parsed(price) ?? original.fuelPrice) : original.fuelPrice
                )
            }
        }

        Haptics.success()
        dismiss()
    }

    private func parsed(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Helpers

    private func consumptionUnitLabel(_ l: LanguageManager.Language) -> String {
        GarageFormat.consumptionUnit(
            volumeRaw: volumeUnit, distanceRaw: distanceUnit, isRu: l == .ru)
    }
}
