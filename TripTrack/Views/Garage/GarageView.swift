import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var settings = SettingsManager.shared

    @State private var showAddVehicle = false
    @State private var detailVehicleId: UUID?
    @State private var deleteCandidateId: UUID?

    var body: some View {
        let c = AppTheme.colors(for: scheme)
        let l = lang.language

        NavigationStack {
            VStack(spacing: 0) {
                navRow(c: c, l: l)
                ScrollView {
                    VStack(spacing: 12) {
                        if settings.vehicles.isEmpty {
                            emptyState(c: c, l: l)
                        } else {
                            vehicleList(c: c, l: l)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailVehicleId) { id in
                VehicleDetailView(vehicleId: id)
            }
            .sheet(isPresented: $showAddVehicle) {
                VehicleEditFormView(mode: .add)
                    .environmentObject(lang)
            }
            .confirmationDialog(
                AppStrings.deleteVehicleConfirm(l),
                isPresented: Binding(
                    get: { deleteCandidateId != nil },
                    set: { if !$0 { deleteCandidateId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(AppStrings.deleteVehicle(l), role: .destructive) {
                    performDelete()
                }
                Button(AppStrings.cancel(l), role: .cancel) {
                    deleteCandidateId = nil
                }
            }
        }
    }

    // MARK: - Nav Row (Figma 152:1328)

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let atCap = settings.vehicles.count >= 5
        return HStack {
            // Garage is presented as a sheet — the chevron acts as close (fork F1).
            GarageCircleNavButton(systemImage: "chevron.left") { dismiss() }
            Spacer()
            Text(AppStrings.garage(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)
            Spacer()
            GarageCircleNavButton(systemImage: "plus") { showAddVehicle = true }
                .disabled(atCap)
                .opacity(atCap ? 0.35 : 1)
                .accessibilityIdentifier("garage_add")
        }
        .padding(.top, 2)
        .padding(.bottom, 10)
        .padding(.horizontal, 16)
    }

    // MARK: - Vehicle List

    @ViewBuilder
    private func vehicleList(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let sorted = settings.vehicles.sorted { $0.odometerKm > $1.odometerKm }
        ForEach(sorted) { vehicle in
            vehicleCard(vehicle, c: c, l: l)
        }
        if settings.vehicles.count >= 5 {
            Text(AppStrings.maxVehiclesHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    // MARK: - Vehicle Card (Figma 152:1349 / 152:1362)

    private func vehicleCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Keep the exact existing main-vehicle fallback semantics.
        let isMain = vehicle.id == (settings.selectedVehicleId ?? settings.vehicles.first?.id)

        return Button {
            Haptics.tap()
            detailVehicleId = vehicle.id
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(c.cardAlt)
                            .frame(width: 64, height: 64)
                        vehicle.avatarView(size: 44)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(c.text)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            if isMain {
                                Text(AppStrings.vehicleMainLabel(l).uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundStyle(c.textSecondary)
                                    .fixedSize()
                            }
                        }

                        Text("\(GarageFormat.odometer(vehicle.odometerKm)) \(AppStrings.km(l))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    VehicleXPBar(progress: vehicle.progressToNextLevel, tint: AppTheme.blue)
                    Text("LVL \(vehicle.level)")
                        .font(.custom("PressStart2P-Regular", size: 8))
                        .foregroundStyle(AppTheme.accent)
                        .fixedSize()
                }
                .padding(.top, 6)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("garage_card")
        .surfaceCard(cornerRadius: 16)
        .overlay {
            if isMain {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppTheme.accent, lineWidth: 2)
            }
        }
        .contextMenu {
            if !isMain {
                Button {
                    settings.selectVehicle(id: vehicle.id)
                } label: {
                    Label(AppStrings.makeMainVehicle(l), systemImage: "star")
                }
            }
            Button(role: .destructive) {
                deleteCandidateId = vehicle.id
            } label: {
                Label(AppStrings.deleteVehicle(l), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "car.fill")
                .font(.system(size: 28))
                .foregroundStyle(c.textTertiary)
            Text(AppStrings.addVehicleTitle(l))
                .font(.system(size: 14))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Actions

    private func performDelete() {
        guard let id = deleteCandidateId else { return }
        settings.deleteVehicle(id: id)
        if settings.selectedVehicleId == id {
            settings.selectVehicle(id: settings.vehicles.first?.id)
        }
        deleteCandidateId = nil
    }
}

// MARK: - Units Settings Card

struct UnitsSettingsCard: View {
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme

    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage(FuelCurrency.storageKey) private var currency: String = FuelCurrency.defaultSymbol

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
