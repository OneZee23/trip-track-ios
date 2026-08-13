import SwiftUI

/// Vehicle detail (Figma 499:119 canon). Presented two ways:
/// pushed inside GarageView's NavigationStack, and as a sheet root from
/// ProfileView — so it carries no NavigationStack of its own (nesting stacks
/// is forbidden) and `dismiss()` covers both pop and sheet close.
struct VehicleDetailView: View {
    let vehicleId: UUID

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var bluetoothDetector = AutoTripService.shared.bluetoothDetector
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var themeManager: ThemeManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showEditForm = false
    /// «…» popover on the vehicle header.
    @State private var showVehicleActions = false
    @State private var showAutoRecordSettings = false
    @State private var showDeleteConfirm = false

    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage(FuelCurrency.storageKey) private var currency: String = FuelCurrency.defaultSymbol

    private var vehicle: Vehicle? {
        settings.vehicles.first { $0.id == vehicleId }
    }

    private var isMain: Bool {
        vehicleId == (settings.selectedVehicleId ?? settings.vehicles.first?.id)
    }

    @ViewBuilder
    /// Popover rows. Each closes first, then acts — presenting a sheet or
    /// an alert in the same runloop as the dismissal races it and SwiftUI
    /// drops one of the two.
    private func vehicleActionItems(_ l: LanguageManager.Language) -> [ActionPopoverList.Item] {
        func run(_ action: @escaping () -> Void) {
            showVehicleActions = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                action()
            }
        }
        var items: [ActionPopoverList.Item] = [
            .init(title: AppStrings.renameVehicle(l), systemImage: "pencil") {
                run { showEditForm = true }
            },
        ]
        if !isMain {
            items.append(
                .init(title: AppStrings.makeMainVehicle(l), systemImage: "star") {
                    run { settings.selectVehicle(id: vehicleId) }
                }
            )
        }
        items.append(
            .init(title: AppStrings.deleteVehicle(l), systemImage: "trash", isDestructive: true) {
                run { showDeleteConfirm = true }
            }
        )
        return items
    }

    var body: some View {
        // `@ViewBuilder` lets us early-return without `AnyView` when the
        // vehicle was deleted out from under the view.
        if let vehicle {
            let c = AppTheme.colors(for: scheme)
            let l = lang.language

            VStack(spacing: 0) {
                navRow(c: c, l: l)
                ScrollView {
                    VStack(spacing: 12) {
                        heroCard(vehicle, c: c, l: l)
                        statGrid(vehicle, c: c, l: l)
                        stickersSection(vehicle, c: c, l: l)
                        // BT-off warning only when it is true AND relevant (fork F12).
                        if settings.autoRecordMode != .off && !bluetoothDetector.isBluetoothAvailable {
                            btWarningChip(c: c, l: l)
                        }
                        autoRecordRow(c: c, l: l)
                        fuelSection(vehicle, c: c, l: l)
                        UnitsSettingsCard()
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .background(c.bg)
            .toolbar(.hidden, for: .navigationBar)
            // Re-enables the interactive pop gesture the hidden nav bar
            // kills — same wiring as TripDetailView/SocialTripDetailView.
            .background(NavBarKiller())
            .sheet(isPresented: $showEditForm) {
                VehicleEditFormView(mode: .edit(vehicleId))
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
            .sheet(isPresented: $showAutoRecordSettings) {
                AutoRecordSettingsView(vehicleId: vehicleId)
                    .environmentObject(lang)
                    .preferredColorScheme(themeManager.preferredColorScheme)
            }
            .confirmationDialog(
                AppStrings.deleteVehicleConfirm(l),
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button(AppStrings.deleteVehicle(l), role: .destructive) {
                    performDelete()
                }
                Button(AppStrings.cancel(l), role: .cancel) {}
            }
        }
    }

    // MARK: - Nav Row

    private func navRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(c.text)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text(AppStrings.myVehicle(l))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.text)

            Spacer()

            // Popover, not a `Menu` — see `ActionPopoverList` for the plate
            // artifact a Menu leaves behind when it closes.
            Button {
                Haptics.tap()
                showVehicleActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(c.text)
                    .frame(width: 34, height: 34)
                    .padding(5)
                    .contentShape(Circle())
                    .padding(-5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.moreActions(l))
            .popover(isPresented: $showVehicleActions, arrowEdge: .top) {
                ActionPopoverList(items: vehicleActionItems(l))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .padding(.horizontal, 12)
    }

    // MARK: - Hero Card

    private func heroCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let year = Calendar.current.component(.year, from: vehicle.createdAt)

        // Canon stacks 96-avatar · 12 · name · 3 · subtitle · 14 · XP row;
        // the block was built with 10/2/14 and read a touch tighter than drawn.
        return VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(c.cardAlt)
                    .frame(width: 96, height: 96)
                vehicle.avatarView(size: 64)
            }

            VStack(spacing: 3) {
                Text(vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.7)
                // Canon (119:968 · 499:137) draws «А123БВ 77 · 2019» here.
                // `Vehicle` carries neither field: a plate would need a new
                // CoreData attribute, a store migration and a server column for
                // one cosmetic line, and the year would be a plate-adjacent
                // invention (`createdAt` is when the car was ADDED, not its
                // model year). Every canvas comparison re-raises this line —
                // the answer is still odometer + «с YYYY» (fork F3, settled).
                Text("\(GarageFormat.odometer(vehicle.odometerKm)) \(AppStrings.km(l)) · \(AppStrings.sinceYear(l, year: year))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }

            HStack(spacing: 8) {
                VehicleXPBar(progress: vehicle.progressToNextLevel, tint: AppTheme.blue)
                Text("LVL \(vehicle.level)")
                    .font(.custom("PressStart2P-Regular", size: 8))
                    .foregroundStyle(AppTheme.blue)
                    .fixedSize()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Stat Grid

    private func statGrid(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // No measured consumption exists — mean of city/highway settings (fork F10).
        let avg = (vehicle.cityConsumption + vehicle.highwayConsumption) / 2

        return HStack(spacing: 10) {
            statCard(
                value: GarageFormat.odometer(vehicle.odometerKm),
                valueColor: c.text,
                unit: AppStrings.km(l),
                label: AppStrings.odometerLabel(l),
                c: c
            )
            statCard(
                value: GarageFormat.oneDecimal(avg, isRu: l == .ru),
                valueColor: AppTheme.green,
                unit: consumptionUnitLabel(l),
                label: AppStrings.avgConsumptionLabel(l),
                c: c
            )
        }
    }

    private func statCard(value: String, valueColor: Color, unit: String, label: String, c: AppTheme.Colors) -> some View {
        // Canon gap between the value row and its caption is 4, not 6.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            GarageSectionLabel(text: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 14)
    }

    // MARK: - Stickers

    private func stickersSection(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Canon puts this header a step above the in-card labels (12/0.36)
            // and starts it on the screen's 14pt gutter — the extra 2pt indent
            // pushed it out of line with the card edges below it.
            GarageSectionLabel(text: AppStrings.stickersLabel(l), size: 12, tracking: 0.36)

            ScrollView(.horizontal, showsIndicators: false) {
                // Canon draws only the three EARNED badges, so it needs no
                // container; showing all ten with locks (fork F11) needs a
                // scroll, and a bare scrolling strip would bleed under both
                // screen edges with nothing to bound it — hence the card. Cell
                // pitch (74 wide, 10 apart, top-aligned) is canon's.
                HStack(alignment: .top, spacing: 10) {
                    ForEach(VehicleSticker.allCases, id: \.self) { sticker in
                        stickerCell(sticker, earned: vehicle.stickers.contains(sticker), c: c, l: l)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func stickerCell(_ sticker: VehicleSticker, earned: Bool, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(earned ? sticker.color.opacity(0.15) : c.cardAlt)
                    .frame(width: 46, height: 46)
                if earned {
                    Image(systemName: sticker.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(sticker.color)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(c.textTertiary.opacity(0.6))
                }
            }
            // Canon wraps the caption over two 70pt lines. One line + a 0.7
            // scale floor shrank «Платиновая рамка»/«Серебряная рамка» — the
            // longest of the ten — to ~7pt while the drawn badge reads at 10.
            Text(l == .ru ? sticker.titleRu() : sticker.titleEn())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(earned ? sticker.color : c.textTertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(width: 70)
        }
        .frame(width: 74)
    }

    // MARK: - BT Warning Chip (Figma canon bg, fork F4/F12)

    private func btWarningChip(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(AppTheme.yellow)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.btOffTitle(l))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(c.text)
                Text(AppStrings.btOffChipBody(l))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                // Public settings URL only — no private deep link (fork F13).
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text(AppStrings.settingsButton(l))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
        .padding(14)
        // Canon fills this one with card-alt instead of card, but it is still a
        // card and carries the same 1pt elevation as the ones above it — the
        // chip was drawn flat and sank into the background.
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(c.cardAlt)
                .shadow(
                    color: scheme == .dark ? .clear : .black.opacity(0.03),
                    radius: 2,
                    y: 1
                )
        }
    }

    // MARK: - Auto-Record Row (undrawn glue, fork F14)

    private func autoRecordRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            showAutoRecordSettings = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15))
                    .foregroundStyle(settings.autoRecordMode != .off ? AppTheme.accent : c.textTertiary)
                Text(AppStrings.autoRecord(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                Spacer()
                Text(autoRecordModeLabel(l))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_autorecord_row")
        .surfaceCard(cornerRadius: 16)
    }

    private func autoRecordModeLabel(_ l: LanguageManager.Language) -> String {
        switch settings.autoRecordMode {
        case .off: return AppStrings.autoRecordOff(l)
        case .remind: return AppStrings.autoRecordRemind(l)
        case .auto: return AppStrings.autoRecordAuto(l)
        }
    }

    // MARK: - Fuel Section

    private func fuelSection(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let isRu = l == .ru
        let consumptionUnit = consumptionUnitLabel(l)
        let priceUnit = "\(currency)/\(GarageFormat.volumeShort(volumeUnit, isRu: isRu))"

        return VStack(alignment: .leading, spacing: 8) {
            // Canon (499:193) keeps this one at the in-card 10/0.5, but on the
            // screen gutter — the 2pt indent misaligned it with the card below.
            GarageSectionLabel(text: AppStrings.fuelSectionLabel(l))

            VStack(spacing: 0) {
                fuelRow(
                    title: AppStrings.fuelCityRow(l),
                    value: "\(GarageFormat.fuel(vehicle.cityConsumption, isRu: isRu)) \(consumptionUnit)",
                    c: c
                )
                fuelDivider(c: c)
                fuelRow(
                    title: AppStrings.fuelHighwayRow(l),
                    value: "\(GarageFormat.fuel(vehicle.highwayConsumption, isRu: isRu)) \(consumptionUnit)",
                    c: c
                )
                fuelDivider(c: c)
                fuelRow(
                    title: AppStrings.fuelPriceRow(l),
                    value: "\(GarageFormat.fuel(vehicle.fuelPrice, isRu: isRu)) \(priceUnit)",
                    c: c
                )
            }
            .surfaceCard(cornerRadius: 16)
        }
    }

    private func fuelRow(title: String, value: String, c: AppTheme.Colors) -> some View {
        Button {
            // Fuel rows open the one drawn editor screen (fork F9).
            showEditForm = true
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fuelDivider(c: AppTheme.Colors) -> some View {
        // Canon (499:199/499:204) runs the rule edge to edge; the 14pt leading
        // inset was a Settings-style habit the card was never drawn with.
        Rectangle()
            .fill(c.cardAlt)
            .frame(height: 1)
    }

    // MARK: - Helpers

    private func consumptionUnitLabel(_ l: LanguageManager.Language) -> String {
        GarageFormat.consumptionUnit(
            volumeRaw: volumeUnit, distanceRaw: distanceUnit, isRu: l == .ru)
    }

    // MARK: - Actions

    private func performDelete() {
        settings.deleteVehicle(id: vehicleId)
        if settings.selectedVehicleId == vehicleId {
            settings.selectVehicle(id: settings.vehicles.first?.id)
        }
        dismiss()
    }
}
