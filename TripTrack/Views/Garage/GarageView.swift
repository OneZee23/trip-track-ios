import SwiftUI

struct GarageView: View {
    @EnvironmentObject private var lang: LanguageManager
    /// Sheets are separate presentations — the override applied to the
    /// Garage sheet itself (ProfileView) does not reach a sheet presented
    /// from HERE, so the add-vehicle form must re-apply it.
    @EnvironmentObject private var themeManager: ThemeManager
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
                // An empty garage is a screen, not a card: it has to own the
                // space under the nav row to centre in it, so it replaces the
                // scroll view instead of living inside it.
                if settings.vehicles.isEmpty {
                    emptyState(c: c, l: l)
                } else {
                    vehicleScroll(c: c, l: l)
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
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
            .confirmationDialog(
                AppStrings.deleteVehicleConfirm(l),
                isPresented: deleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(AppStrings.deleteVehicle(l), role: .destructive) {
                    performDelete()
                }
                Button(AppStrings.cancel(l), role: .cancel) {
                    deleteCandidateId = nil
                }
            } message: {
                // Without it the sheet asks to delete and says nothing about
                // what happens to the trips — the one thing worth fearing.
                Text(AppStrings.deleteVehicleBody(l))
            }
        }
    }

    private var deleteConfirmation: Binding<Bool> {
        Binding(
            get: { deleteCandidateId != nil },
            set: { if !$0 { deleteCandidateId = nil } }
        )
    }

    // MARK: - Nav Row (Figma 152:1328)

    /// The app's own nav bar, not a local copy of one.
    ///
    /// This row used to be hand-built from `GarageCircleNavButton` — a 34pt
    /// circle like the canon control but with a fainter shadow, a smaller
    /// glyph and no 44pt hit area — inset 2pt from the top. On a sheet, whose
    /// top edge is a hard rounded boundary with UIKit's grabber over the first
    /// 10pt, 2pt glued the buttons into the corner and clipped them against
    /// it. `CustomNavBar` already solves exactly this: it insets 20pt inside a
    /// sheet for the grabber, 20pt horizontally so the controls clear the
    /// curved glass, and it carries `NavCircleIcon` — the same control every
    /// other sheet in the app uses.
    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let atCap = settings.vehicles.count >= 5
        return CustomNavBar(title: AppStrings.garage(l)) {
            Button {
                Haptics.tap()
                showAddVehicle = true
            } label: {
                NavCircleIcon(systemImage: "plus")
            }
            .buttonStyle(.plain)
            .disabled(atCap)
            .opacity(atCap ? 0.35 : 1)
            .accessibilityIdentifier("garage_add")
        }
        // Presented as a sheet from Profile, Settings and the Feed — the bar
        // needs to know so it clears the grabber.
        .environment(\.navBarInSheet, true)
    }

    // MARK: - Vehicle List

    private func vehicleScroll(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                vehicleList(c: c, l: l)
            }
            .padding(.horizontal, 16)
            // The first card sat flush against the nav row, so the
            // highlighted one read as growing out of it.
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
    }

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
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(c.cardAlt)
                        .frame(width: 64, height: 64)
                    vehicle.avatarView(size: 44)
                }

                VStack(alignment: .leading, spacing: 6) {
                    nameRow(vehicle, isMain: isMain, c: c, l: l)
                    identityLine(vehicle, c: c, l: l)

                    // The level line lives in this column, not across the
                    // whole card. Run full-bleed under the avatar it reads
                    // as a loading bar the card is waiting on; kept beside
                    // the name it reads as one more fact about the car,
                    // which is what it is.
                    HStack(spacing: 10) {
                        // Bar and pill share the decade colour: two
                        // different colours for one level would read as
                        // two facts.
                        VehicleXPBar(
                            progress: vehicle.progressToNextLevel,
                            tint: vehicle.levelColor
                        )
                        VehicleLevelPill(level: vehicle.level, size: 9)
                    }
                    .padding(.top, 2)
                }
                // The checkmark is trailing-aligned inside the name row,
                // so the column has to take the full card width instead
                // of being pushed left by a Spacer beside it.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("garage_card")
        .background {
            // Drawn before `surfaceCard` so it lands ON the card fill rather
            // than behind it — the peach wash is what marks the main vehicle
            // at a glance; the border alone is easy to miss on a warm bg.
            if isMain {
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppTheme.accentBg)
            }
        }
        .surfaceCard(cornerRadius: 16)
        .overlay {
            if isMain {
                // `strokeBorder`, not `stroke`: stroke centres the line on the
                // card's edge, so half of it lies OUTSIDE the bounds and the
                // scroll view clips it — most visibly along the top, where the
                // content has no inset to spare. strokeBorder keeps the whole
                // line inside.
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
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

    private func nameRow(
        _ vehicle: Vehicle,
        isMain: Bool,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        HStack(spacing: 6) {
            Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.tail)

            // Hidden transport is still fully usable here, so the only cue the
            // owner gets that others cannot see it is this lock.
            if !vehicle.visibleToOthers {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .accessibilityLabel(AppStrings.vehicleHiddenFromOthers(l))
            }

            Spacer(minLength: 8)

            if isMain {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.accent)
                    .accessibilityLabel(AppStrings.vehicleMainLabel(l))
            }
        }
    }

    /// The plate is the card's identity line — but it is optional, and bikes
    /// and mopeds never carry one, so the odometer takes the slot instead of
    /// letting the card change height from vehicle to vehicle.
    @ViewBuilder
    private func identityLine(
        _ vehicle: Vehicle,
        c: AppTheme.Colors,
        l: LanguageManager.Language
    ) -> some View {
        if vehicle.hasPlate {
            // The owner's own screen — `plate`, not `publicPlate`, which is
            // about what everyone else may see.
            VehiclePlateChip(plate: vehicle.plate)
        } else {
            Text("\(GarageFormat.odometer(vehicle.odometerKm)) \(AppStrings.km(l))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(c.textTertiary)
        }
    }

    // MARK: - Empty State

    private func emptyState(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 14) {
            // The asset is 254×188; a square frame would letterbox it, so only
            // the width is pinned. `.interpolation` sits after `.resizable()`
            // like every other pixel-art call site in the app — `resizable()`
            // rebuilds the Image, and a nearest-neighbour hint set before it
            // is not guaranteed to survive that.
            Image("pixel_car_orange")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 96)

            VStack(spacing: 8) {
                Text(AppStrings.garageEmptyTitle(l))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.garageEmptyBody(l))
                    .font(.system(size: 14))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Haptics.tap()
                showAddVehicle = true
            } label: {
                Text(AppStrings.addVehicleTitle(l))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("garage_empty_add")
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        // Dead centre of the remaining space sits low once the nav row has
        // taken the top of the sheet, so the block is lifted a notch.
        .padding(.bottom, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
