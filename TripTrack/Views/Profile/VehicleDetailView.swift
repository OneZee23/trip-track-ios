import SwiftUI

/// Vehicle detail (Figma 499:119 canon). Pushed inside GarageView's
/// NavigationStack — it carries no NavigationStack of its own (nesting stacks
/// is forbidden) and `dismiss()` pops it.
///
/// It now needs that host stack rather than merely tolerating one: the level
/// row pushes `VehicleLevelInfoView` into it, so this view cannot be used as a
/// bare sheet root.
struct VehicleDetailView: View {
    let vehicleId: UUID

    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var bluetoothDetector = AutoTripService.shared.bluetoothDetector
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showEditForm = false
    /// «…» popover on the vehicle header.
    @State private var showVehicleActions = false
    @State private var showAutoRecordSettings = false
    @State private var showDeleteConfirm = false
    @State private var showLevelInfo = false
    /// Name of the Bluetooth audio device the phone is playing through,
    /// refreshed whenever the route changes. Nil when nothing is connected.
    @State private var connectedStereo: String?

    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage(ConsumptionUnit.storageKey)
    private var consumptionUnitRaw: String = ConsumptionUnit.per100.rawValue
    @AppStorage(FuelCurrency.storageKey) private var currency: String = FuelCurrency.defaultSymbol

    private var vehicle: Vehicle? {
        settings.vehicles.first { $0.id == vehicleId }
    }

    private var isMain: Bool {
        vehicleId == (settings.selectedVehicleId ?? settings.vehicles.first?.id)
    }

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
        // «Редактировать», not «Переименовать»: the form it opens edits the
        // type, the plate and its visibility too — the old title promised only
        // the name field.
        var items: [ActionPopoverList.Item] = [
            .init(title: AppStrings.edit(l), systemImage: "pencil") {
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
                navRow(title: displayName(vehicle, l), c: c, l: l)
                ScrollView {
                    VStack(spacing: 12) {
                        heroCard(vehicle, c: c, l: l)
                        statGrid(vehicle, c: c, l: l)
                        // A bicycle pairs with no stereo, so auto-record has
                        // nothing to key off — the rows are absent, not
                        // disabled (canon: hidden means gone).
                        if vehicle.type.supportsAutoRecord {
                            // Always present, never conditional. It used to
                            // appear only when Bluetooth was off AND
                            // auto-record was armed, which meant its silence
                            // carried two opposite meanings — "all good" and
                            // "nothing is set up" — and the card gave no way
                            // to tell them apart at a glance.
                            stereoStatusCard(c: c, l: l)
                            autoRecordRow(c: c, l: l)
                        }
                        // Same for fuel: a bicycle burns none.
                        if vehicle.type.burnsFuel {
                            fuelSection(vehicle, c: c, l: l)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .padding(.bottom, 96)
                }
                .scrollIndicators(.hidden)
            }
            .background(c.bg)
            .task { connectedStereo = AudioRouteDetector.currentBluetoothOutputName() }
            // The stereo connects and drops while this screen is open — the
            // card claims «подключена», so it has to keep earning it.
            .onReceive(NotificationCenter.default.publisher(
                for: AudioRouteDetector.routeChangeNotification)) { _ in
                connectedStereo = AudioRouteDetector.currentBluetoothOutputName()
            }
            .toolbar(.hidden, for: .navigationBar)
            // Re-enables the interactive pop gesture the hidden nav bar
            // kills — same wiring as TripDetailView/SocialTripDetailView.
            .background(NavBarKiller())
            // Pushed, not presented: the level screen is a chapter of this one,
            // and the Garage stack that hosts this view hosts it too.
            .navigationDestination(isPresented: $showLevelInfo) {
                VehicleLevelInfoView(level: vehicle.level, odometerKm: vehicle.odometerKm)
            }
            .sheet(isPresented: $showEditForm) {
                VehicleEditFormView(mode: .edit(vehicleId))
                    .environmentObject(lang)
            }
            .sheet(isPresented: $showAutoRecordSettings) {
                AutoRecordSettingsView(vehicleId: vehicleId)
                    .environmentObject(lang)
            }
            // House dialog, never the system's — see «Dialogs» in CLAUDE.md.
            // The card dismisses itself before the handler runs, so the pop
            // `performDelete` does happens with nothing left over the screen.
            .appConfirm(
                isPresented: $showDeleteConfirm,
                title: AppStrings.deleteVehicleConfirm(l),
                // The one thing someone deleting a car is actually afraid of.
                message: AppStrings.deleteVehicleBody(l),
                actions: [
                    AppDialogAction(AppStrings.deleteVehicle(l), kind: .destructive) {
                        performDelete()
                    }
                ],
                cancelTitle: AppStrings.cancel(l)
            )
        }
    }

    // MARK: - Nav Row

    /// The app's own bar, not a local copy of one.
    ///
    /// This row was hand-built: bare glyphs in 34pt frames with 4pt of top
    /// padding and a 16pt title. Next to the Garage's `CustomNavBar` — which
    /// this screen is one push away from — it read as a different, thinner
    /// app. `CustomNavBar` carries the circle controls, the 44pt hit areas,
    /// the sheet-grabber clearance and the `NavBarKiller` that keeps the
    /// interactive pop gesture alive.
    private func navRow(title: String, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        CustomNavBar(title: title) {
            // Popover, not a `Menu` — see `ActionPopoverList` for the plate
            // artifact a Menu leaves behind when it closes.
            Button {
                Haptics.tap()
                showVehicleActions = true
            } label: {
                NavCircleIcon(systemImage: "ellipsis")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.moreActions(l))
            .popover(isPresented: $showVehicleActions, arrowEdge: .top) {
                ActionPopoverList(items: vehicleActionItems(l))
            }
        }
    }

    // MARK: - Hero Card

    /// Avatar, name, plate, level. Nothing else.
    ///
    /// It also carried «295 км · с 2026». The odometer is the stat card
    /// directly below it, so the line repeated the screen's own next row, and
    /// the year was never a fact about the car — `createdAt` is when it was
    /// added to the garage, which for an eight-year-old Polo reads as a lie.
    private func heroCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(spacing: 0) {
            // The car is the subject of the screen, so it gets the room. It
            // used to sit in a 96 pt tile above an 18 pt name and a full-width
            // level bar, and the bar — the widest, heaviest object on the card
            // — read as the headline. The order of weight is the car, then its
            // name, then everything else.
            // Landscape, not a square. The car is wide, and a square plate
            // big enough to show it properly turns into a wall of navy on a
            // light screen — which is what «too dark, too heavy» actually was.
            // Cropped to the car's own proportions the dark area roughly
            // halves and the sprite is framed rather than floated.
            VehicleSpritePlate(
                assetName: vehicle.avatarImageName,
                fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                plateSize: heroPlateWidth,
                cornerRadius: 20
            )
            .padding(.top, 4)

            Text(displayName(vehicle, l))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.6)
                .padding(.top, 16)

            if vehicle.hasPlate {
                // The owner always sees their own plate here. `plateVisible`
                // is about OTHER people (see `Vehicle.publicPlate`) — hiding
                // it from the person who typed it in would be theatre.
                VehiclePlateChip(plate: vehicle.plate)
                    .padding(.top, 8)
            }

            levelRow(vehicle, c: c)
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .surfaceCard(cornerRadius: 20)
    }

    /// Sized off the screen rather than pinned, so the car stays the biggest
    /// thing on the card on an SE and does not swallow the fold on a Max.
    private var heroPlateWidth: CGFloat {
        min(max(UIScreen.main.bounds.width * 0.62, 210), 280)
    }

    // MARK: - Level Row

    /// Bar + «LVL 28», both in the decade colour, the whole strip a way into
    /// «Уровень машины».
    ///
    /// The pair used to be a fixed blue, which made the colour decoration. It
    /// carries the level's own decade now, so the number and its bar say the
    /// same thing twice — and the chevron admits there is more to read.
    private func levelRow(_ vehicle: Vehicle, c: AppTheme.Colors) -> some View {
        Button {
            Haptics.tap()
            showLevelInfo = true
        } label: {
            HStack(spacing: 8) {
                VehicleLevelPill(level: vehicle.level)
                // Thinner and no longer full-bleed. Stretched across the card
                // it was the widest, heaviest object on a screen whose subject
                // is the car — the progress towards the next level is a
                // footnote about the car, not the headline above it.
                VehicleXPBar(progress: vehicle.progressToNextLevel, tint: vehicle.levelColor, height: 4)
                    .frame(maxWidth: 140)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            // Pad → shape → unpad: a 6pt bar is a 6pt hit target otherwise,
            // and canon's 14pt gap above the row must not grow (same idiom as
            // the «…» button in the nav row).
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .padding(.vertical, -10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_level_row")
        .padding(.top, 2)
    }

    // MARK: - Stat Grid

    private func statGrid(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // No measured consumption exists — mean of city/highway settings (fork F10).
        // Averaged BEFORE conversion: mpg is a reciprocal, so the mean of
        // two mpg figures is not the mpg of the mean consumption.
        let avg = shownConsumption((vehicle.cityConsumption + vehicle.highwayConsumption) / 2)

        return HStack(spacing: 10) {
            statCard(
                value: GarageFormat.odometer(vehicle.odometerKm),
                valueColor: c.text,
                unit: AppStrings.km(l),
                label: AppStrings.odometerLabel(l),
                c: c
            )
            // Consumption is a fuel figure like the ones below it, so a
            // bicycle drops it too — the odometer card then takes the row.
            if vehicle.type.burnsFuel {
                statCard(
                    value: GarageFormat.oneDecimal(avg, lng: l),
                    valueColor: AppTheme.green,
                    unit: consumptionUnitLabel(l),
                    label: AppStrings.avgConsumptionLabel(l),
                    c: c
                )
            }
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

    // MARK: - BT Warning Chip (Figma canon bg, fork F4/F12)

    /// Where the car stereo stands, always stated.
    ///
    /// Three facts, three faces: Bluetooth is off, no stereo is linked, or one
    /// is linked — and if the phone is playing through it right now, connected.
    /// The old card showed only the first, and only while auto-record was
    /// armed, so «no card» meant both "everything is fine" and "nothing is set
    /// up" and the screen never answered «подключён ли блютуз» at a glance.
    ///
    /// «Подключена» is read from the AUDIO ROUTE, not from BLE scanning: a car
    /// stereo is a classic-Bluetooth sink that CoreBluetooth never sees, and
    /// it is the route that auto-record itself keys off.
    @ViewBuilder
    private func stereoStatusCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let linked = settings.bluetoothDevice(forVehicle: vehicleId)
        let isConnected = linked.map { $0.name == connectedStereo } ?? false

        if !bluetoothDetector.isBluetoothAvailable {
            stereoRow(
                icon: "antenna.radiowaves.left.and.right.slash",
                tint: AppTheme.red,
                title: AppStrings.btOffTitle(l),
                subtitle: AppStrings.btOffChipBody(l),
                c: c
            ) {
                // Public settings URL only — no private deep link (fork F13).
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Text(AppStrings.settingsButton(l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.accentBg, in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        } else if let linked {
            stereoRow(
                icon: "antenna.radiowaves.left.and.right",
                tint: isConnected ? AppTheme.green : c.textTertiary,
                title: isConnected
                    ? AppStrings.stereoConnectedTitle(l)
                    : AppStrings.stereoLinkedTitle(l),
                subtitle: "\(linked.name) · " + (isConnected
                    ? AppStrings.stereoStartsItself(l)
                    : AppStrings.stereoStartsOnConnect(l)),
                c: c
            ) {
                // Connected is the resting state — nothing to do, so nothing
                // to press. A button here would only ever undo something.
                EmptyView()
            }
        } else {
            stereoRow(
                icon: "antenna.radiowaves.left.and.right",
                tint: c.textTertiary,
                title: AppStrings.stereoNotLinkedTitle(l),
                subtitle: AppStrings.stereoNotLinkedBody(l),
                c: c
            ) {
                Button {
                    Haptics.tap()
                    showAutoRecordSettings = true
                } label: {
                    Text(AppStrings.linkStereo(l))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(AppTheme.accentBg, in: Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    /// One shape for all three states — the icon's colour is what changes, so
    /// the row is recognised before it is read.
    private func stereoRow<Action: View>(
        icon: String,
        tint: Color,
        title: String,
        subtitle: String,
        c: AppTheme.Colors,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            action()
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .accessibilityIdentifier("vehicle_stereo_status")
    }

    private func autoRecordRow(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        Button {
            Haptics.tap()
            showAutoRecordSettings = true
        } label: {
            // No leading glyph: the stereo card directly above already
            // carries the Bluetooth icon, and two antennas one under the
            // other read as two different subjects.
            HStack(spacing: 10) {
                Text(AppStrings.autoRecord(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                Spacer()
                Text(autoRecordStateLabel(l))
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

    /// On/Off, not the mode name: this row answers «is it armed?». Which of the
    /// two armed modes is running is the auto-record screen's own headline, one
    /// tap away, and naming it here made «Напоминание» look like a state of the
    /// vehicle rather than a setting.
    private func autoRecordStateLabel(_ l: LanguageManager.Language) -> String {
        settings.autoRecordMode == .off
            ? AppStrings.autoRecordOff(l)
            : AppStrings.autoRecordOn(l)
    }

    // MARK: - Fuel Section

    private func fuelSection(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let lng = l
        let consumptionUnit = consumptionUnitLabel(l)
        // Per litre or per gallon by the same choice that picks л/100 vs mpg —
        // and the number converts with it. The vehicle currency, not the
        // app-wide one: each vehicle owns its price.
        let priceUnit = "\(vehicle.fuelCurrency)/"
            + GarageFormat.volumeShort(shownConsumptionUnit.volumeUnit.rawValue, lng: lng)

        return VStack(alignment: .leading, spacing: 8) {
            // Canon (499:193) keeps this one at the in-card 10/0.5, but on the
            // screen gutter — the 2pt indent misaligned it with the card below.
            GarageSectionLabel(text: AppStrings.fuelSectionLabel(l))

            VStack(spacing: 0) {
                fuelRow(
                    title: AppStrings.fuelCityRow(l),
                    value: "\(GarageFormat.fuel(shownConsumption(vehicle.cityConsumption), lng: lng)) \(consumptionUnit)",
                    c: c
                )
                fuelDivider(c: c)
                fuelRow(
                    title: AppStrings.fuelHighwayRow(l),
                    value: "\(GarageFormat.fuel(shownConsumption(vehicle.highwayConsumption), lng: lng)) \(consumptionUnit)",
                    c: c
                )
                fuelDivider(c: c)
                fuelRow(
                    title: AppStrings.fuelPriceRow(l),
                    value: "\(GarageFormat.fuel(shownConsumptionUnit.displayPrice(fromPerLitre: vehicle.fuelPrice), lng: lng)) \(priceUnit)",
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

    /// One name for the nav row and the hero, so an unnamed vehicle does not
    /// read «Без имени» in one and blank in the other.
    private func displayName(_ vehicle: Vehicle, _ l: LanguageManager.Language) -> String {
        vehicle.name.isEmpty ? AppStrings.unnamedVehicle(l) : vehicle.name
    }

    /// The dialect chosen in the vehicle form. Kept in step with it on
    /// purpose: the card showing «9,1 л/100 км» while the form that set the
    /// figure shows «25,8 mpg» would read as two different cars.
    private var shownConsumptionUnit: ConsumptionUnit {
        ConsumptionUnit(rawValue: consumptionUnitRaw) ?? .per100
    }

    private func consumptionUnitLabel(_ l: LanguageManager.Language) -> String {
        shownConsumptionUnit.valueUnit(
            volumeRaw: volumeUnit, distanceRaw: distanceUnit, lng: l)
    }

    /// A stored per-100 figure, expressed in whatever unit is on screen.
    private func shownConsumption(_ per100: Double) -> Double {
        shownConsumptionUnit.display(fromPer100: per100)
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
