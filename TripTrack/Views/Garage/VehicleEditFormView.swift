import SwiftUI

/// Shared add/edit vehicle form (Figma «06 · Я · Гараж · Добавить», 500:129 add
/// / 541:119 edit). Presented as a sheet from the garage «+» (add) and from the
/// vehicle detail menu and fuel rows (edit).
///
/// The transport TYPE drives the shape of the form: a moped has no plate and a
/// bicycle burns nothing, so those sections are absent rather than
/// present-and-meaningless. Everything below the type tiles reacts to them.
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
    @State private var selectedType: VehicleType
    @State private var plate: String
    /// Off by default, and never inferred from `visibleToOthers`: in Russia a
    /// plate is enough to look up the owner's name and address, so showing it
    /// has to be its own deliberate answer.
    @State private var plateVisible: Bool
    @State private var visibleToOthers: Bool
    /// Always a real avatar — either a `pixel_car_*` asset name or, for a
    /// vehicle created before the pixel cars replaced the emoji set, that
    /// vehicle's emoji. It used to be optional to keep an unpicked pixel avatar
    /// from being clobbered by a grid that offered emoji only; the grid offers
    /// the pixel cars themselves now, so the selection can say what it means.
    /// Holds the COLOUR, and stays a legacy-drawable name. The silhouette
    /// lives beside it rather than inside it — see `VehicleAvatar`.
    @State private var selectedAvatar: String
    @State private var selectedAvatarStyle: String
    @State private var city: String
    @State private var highway: String
    @State private var price: String
    /// Per-vehicle, not the app-wide default: a second car can live in a second
    /// country. Held here until save because a new vehicle has no id yet.
    @State private var currencySymbol: String
    @State private var showCurrencyPicker = false
    /// Initial DISPLAY strings — fuel writes fire only when the text
    /// actually changed. Comparing parsed(display) against the stored
    /// full-precision doubles silently rounded e.g. 9.15 → 9.2 on a
    /// name-only save (and enqueued a spurious sync op).
    @State private var initialCity: String
    @State private var initialHighway: String
    @State private var initialPrice: String

    @AppStorage("volumeUnit") private var volumeUnit: String = "liters"
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    @AppStorage(ConsumptionUnit.storageKey)
    private var consumptionUnitRaw: String = ConsumptionUnit.per100.rawValue

    /// Snapshot of the edited vehicle taken at init — used for
    /// changed-only saves so SyncEnqueuer isn't churned needlessly.
    private let editedVehicle: Vehicle?

    private static let avatarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(mode: Mode) {
        self.mode = mode
        let lng = LanguageManager.currentLanguage
        // The fields hold what a person reads, which may be mpg; storage
        // is always per-100. Read the preference straight from defaults —
        // @AppStorage is not available yet at init time.
        let shownUnit = ConsumptionUnit.current

        if case .edit(let id) = mode,
           let vehicle = SettingsManager.shared.vehicles.first(where: { $0.id == id }) {
            editedVehicle = vehicle
            _name = State(initialValue: vehicle.name)
            _selectedType = State(initialValue: vehicle.type)
            _plate = State(initialValue: vehicle.plate)
            _plateVisible = State(initialValue: vehicle.plateVisible)
            _visibleToOthers = State(initialValue: vehicle.visibleToOthers)
            _selectedAvatar = State(initialValue: vehicle.avatarEmoji)
            _selectedAvatarStyle = State(
                initialValue: VehicleAvatar.resolveStyle(vehicle.avatarStyle, forType: vehicle.type.rawValue)
            )
            _currencySymbol = State(initialValue: vehicle.fuelCurrency)
            _city = State(initialValue: GarageFormat.fuel(
                shownUnit.display(fromPer100: vehicle.cityConsumption), lng: lng))
            _highway = State(initialValue: GarageFormat.fuel(
                shownUnit.display(fromPer100: vehicle.highwayConsumption), lng: lng))
            _price = State(initialValue: GarageFormat.fuel(
                shownUnit.displayPrice(fromPerLitre: vehicle.fuelPrice), lng: lng))
        } else {
            editedVehicle = nil
            let defaults = Vehicle()
            _name = State(initialValue: "")
            _selectedType = State(initialValue: .car)
            _plate = State(initialValue: "")
            _plateVisible = State(initialValue: false)
            _visibleToOthers = State(initialValue: true)
            // Canon draws the FIRST grid cell selected by default.
            _selectedAvatar = State(initialValue: VehicleAvatar.legacyName(color: VehicleAvatar.defaultColor))
            _selectedAvatarStyle = State(initialValue: VehicleAvatar.defaultStyle)
            _currencySymbol = State(initialValue: FuelCurrency.current)
            _city = State(initialValue: GarageFormat.fuel(
                shownUnit.display(fromPer100: defaults.cityConsumption), lng: lng))
            _highway = State(initialValue: GarageFormat.fuel(
                shownUnit.display(fromPer100: defaults.highwayConsumption), lng: lng))
            _price = State(initialValue: GarageFormat.fuel(
                shownUnit.displayPrice(fromPerLitre: defaults.fuelPrice), lng: lng))
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
                    typeCard(c: c, l: l)
                    if selectedType.hasPlate {
                        plateCard(c: c, l: l)
                    }
                    avatarCard(c: c, l: l)
                    if selectedType.burnsFuel {
                        fuelCard(c: c, l: l)
                        priceCard(c: c, l: l)
                    }
                    privacyCard(c: c, l: l)
                    if let vehicle = editedVehicle {
                        mileageCard(vehicle, c: c, l: l)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.2), value: selectedType)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(c.bg)
        .safeAreaInset(edge: .bottom) {
            saveButton(l: l)
        }
        // Deliberately NOT `.contentSizedSheet`: that modifier measures what it
        // wraps, and a ScrollView reports whatever height it was handed — the
        // detent would end up feeding its own measurement. The full-height sheet
        // has no dead space anyway, because the Save bar is a bottom safe-area
        // inset and the scroll view takes everything above it.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCurrencyPicker) {
            FuelCurrencyPickerSheet(selectedSymbol: $currencySymbol)
                .environmentObject(lang)
                // A sheet over a sheet does not inherit the theme override, and
                // `scheme` is already the resolved one.
                .preferredColorScheme(scheme)
        }
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
                    SheetCloseCircle()
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
        // Not «Мой автомобиль»: the garage holds transport now, and a moped
        // opening a sheet that calls itself a car is exactly the wording the
        // canon retired. `edit` is also the label on the menu item that opens
        // this sheet, so the title repeats the tap that got here.
        case .edit: return AppStrings.editVehicleTitle(l)
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

    // MARK: - Type

    private func typeCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.vehicleTypeSection(l), color: c.textSecondary)
            HStack(spacing: 8) {
                // Iterated, not hand-written: the canon calls the selector
                // extendable, so a fifth type must land here for free.
                ForEach(VehicleType.allCases) { type in
                    typeTile(type, c: c, l: l)
                }
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func typeTile(_ type: VehicleType, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let isSelected = selectedType == type
        return Button {
            Haptics.selection()
            selectedType = type
            // The silhouette follows the type it belongs to. Without this,
            // calling a vehicle a motorcycle leaves a saloon sitting in the
            // preview — which is exactly what it did on the first build.
            selectedAvatarStyle = VehicleAvatar.resolveStyle(selectedAvatarStyle, forType: type.rawValue)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? AppTheme.accent : c.textSecondary)
                Text(type.label(l))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? c.text : c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? AppTheme.accent.opacity(0.12) : c.cardAlt)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_type_\(type.rawValue)")
    }

    // MARK: - Plate

    private func plateCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let preview = VehiclePlate.normalized(plate)
        return VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.plateSection(l), color: c.textSecondary)

            TextField(AppStrings.platePlaceholder(l), text: $plate)
                .font(.system(size: 15, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(c.text)
                .tint(AppTheme.accent)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                // No mask and no country guess — `sanitize` only drops what
                // cannot be part of a plate anywhere (emoji above all) and caps
                // the length, so the field shows exactly what will be stored.
                .onChange(of: plate) { _, newValue in
                    let cleaned = VehiclePlate.sanitize(newValue)
                    if cleaned != newValue { plate = cleaned }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("vehicle_plate_field")

            toggleRow(
                AppStrings.plateShowToOthers(l),
                isOn: $plateVisible,
                c: c,
                identifier: "vehicle_plate_visible_toggle"
            )

            // The preview answers the only question the toggle raises — "what
            // will they see?" — so it exists only while the answer is "this".
            if plateVisible, !preview.isEmpty {
                VehiclePlateChip(plate: preview)
            }

            Text(plateVisible ? AppStrings.plateVisibilityHintOn(l) : AppStrings.plateVisibilityHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.15), value: plateVisible)
    }

    // MARK: - Avatar

    /// Two axes, not one grid. The old picker offered eight finished pictures,
    /// which meant every new colour was a drawing and every new silhouette was
    /// eight drawings. Splitting the choice into «what it is» and «what colour
    /// it is» makes the two sides independent: a colour costs a ramp, a
    /// silhouette costs one sprite.
    ///
    /// The hero on top is the whole point of the arrangement — at swatch size
    /// nobody can see what they picked, so the selection is shown once, large,
    /// and the rows below are just controls.
    private func avatarCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GarageSectionLabel(text: AppStrings.avatarSection(l), color: c.textSecondary)

            HStack {
                Spacer(minLength: 0)
                avatarHero(c: c)
                Spacer(minLength: 0)
            }

            // Hidden while only one silhouette exists: a row holding a single
            // tile reads as a choice that has been taken away.
            let stylesForType = VehicleAvatar.styles(forType: selectedType.rawValue)
            if stylesForType.count > 1 {
                GarageSectionLabel(text: AppStrings.avatarStyleSection(l), color: c.textSecondary)
                LazyVGrid(columns: Self.avatarColumns, spacing: 8) {
                    ForEach(stylesForType, id: \.self) { style in
                        avatarCell(isSelected: selectedStyle == style, c: c) {
                            selectedAvatarStyle = style
                        } content: {
                            // Drawn in the colour that is currently chosen, so
                            // the row shows shapes rather than a paint chart.
                            Image(VehicleAvatar.compose(style: style, color: selectedColor))
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 10)
                        }
                        // The tile is a picture; VoiceOver has nothing to read
                        // without this and announces seven identical buttons.
                        .accessibilityLabel(AppStrings.avatarStyleName(l, style: style))
                    }
                }
            }

            GarageSectionLabel(text: AppStrings.avatarColorSection(l), color: c.textSecondary)
            colorRow(c: c)
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .animation(.easeInOut(duration: 0.15), value: selectedAvatar)
        .animation(.easeInOut(duration: 0.15), value: selectedAvatarStyle)
    }

    @ViewBuilder
    private func avatarHero(c: AppTheme.Colors) -> some View {
        if let asset = previewAssetName {
            Image(asset)
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 132, height: 88)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
        } else {
            // A vehicle saved before the sprites replaced the emoji set.
            Text(selectedAvatar)
                .font(.system(size: 56))
                .frame(height: 88)
        }
    }

    private func colorRow(c: AppTheme.Colors) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // The old emoji keeps a seat at the front rather than being
                // dropped: opening the form must never silently restyle a
                // vehicle somebody chose on purpose.
                if let legacy = legacyAvatar {
                    swatchButton(isSelected: selectedAvatar == legacy, c: c) {
                        selectedAvatar = legacy
                    } fill: {
                        Circle()
                            .fill(c.cardAlt)
                            .overlay(Text(legacy).font(.system(size: 17)))
                    }
                }
                ForEach(VehicleAvatar.colors, id: \.self) { color in
                    let rgb = VehicleAvatar.swatch(color)
                    swatchButton(isSelected: selectedColor == color && VehicleAvatar.isAsset(selectedAvatar), c: c) {
                        selectedAvatar = VehicleAvatar.legacyName(color: color)
                    } fill: {
                        Circle()
                            .fill(Color(red: rgb.r, green: rgb.g, blue: rgb.b))
                            .overlay(
                                Circle().stroke(
                                    VehicleAvatar.swatchNeedsBorder(color) ? c.textTertiary.opacity(0.35) : .clear,
                                    lineWidth: 1
                                )
                            )
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    /// 34 pt of paint inside a 44 pt target — the ring sits outside the dot
    /// with a gap so the selected colour is never squeezed by its own marker.
    private func swatchButton<Fill: View>(
        isSelected: Bool,
        c: AppTheme.Colors,
        onTap: @escaping () -> Void,
        @ViewBuilder fill: () -> Fill
    ) -> some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            fill()
                .frame(width: 34, height: 34)
                .overlay(
                    Circle()
                        .stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
                        .padding(-4)
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    /// Which silhouette and which colour the current selection decomposes to.
    /// A legacy emoji parses to neither, so both fall back to the defaults —
    /// which is what makes the first tap on any swatch move the vehicle onto
    /// the sprite set instead of doing nothing.
    private var selectedStyle: String { selectedAvatarStyle }

    private var selectedColor: String {
        VehicleAvatar.color(of: selectedAvatar)
    }

    /// What the hero and the style tiles actually draw.
    private var previewAssetName: String? {
        VehicleAvatar.assetName(style: selectedAvatarStyle, avatar: selectedAvatar)
    }

    /// The emoji an existing vehicle was created with, when it is not one of the
    /// pixel cars. Nil for new vehicles and for anything already on the new set.
    private var legacyAvatar: String? {
        guard let vehicle = editedVehicle, !vehicle.isPixelAvatar else { return nil }
        return vehicle.avatarEmoji
    }

    private func avatarCell<Content: View>(
        isSelected: Bool,
        c: AppTheme.Colors,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    // The tile holds a sprite, so it takes the sprite's ground
                    // rather than the card's — otherwise the white and silver
                    // bodies vanish out of the picker in the light theme, which
                    // is the one place a person is deliberately comparing them.
                    RoundedRectangle(cornerRadius: 12)
                        .fill(LinearGradient(
                            colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? AppTheme.accent.opacity(0.14) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? AppTheme.accent : .clear, lineWidth: 2)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Fuel

    private func fuelCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        let unit = consumptionUnitLabel(l)
        // 50 л/100 км is an absurd car; 50 mpg is an ordinary one. The ceiling
        // has to speak the unit on screen or the field would refuse a perfectly
        // normal figure the moment someone switched to mpg.
        let ceiling: Double = consumptionUnit == .mpg ? 250 : 50
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                GarageSectionLabel(text: AppStrings.fuelSectionLabel(l), color: c.textSecondary)
                Spacer(minLength: 8)
                consumptionUnitSegment(c: c, l: l)
            }
            fuelInputRow(label: AppStrings.fuelCity(l), text: $city, maxValue: ceiling, c: c) {
                unitLabel(unit, c: c)
            }
            fuelInputRow(label: AppStrings.fuelHighway(l), text: $highway, maxValue: ceiling, c: c) {
                unitLabel(unit, c: c)
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    /// «л/100 | mpg».
    ///
    /// Switching it CONVERTS what is in the fields — it does not relabel them.
    /// The two units run in opposite directions (9,1 л/100 км is 25,8 mpg), so
    /// a relabel would turn a frugal car into a thirsty one on a tap. What gets
    /// stored is litres per 100 km either way; this only chooses the dialect.
    private func consumptionUnitSegment(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        HStack(spacing: 2) {
            ForEach(ConsumptionUnit.allCases) { unit in
                let selected = unit == consumptionUnit
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    convertFuelFields(to: unit)
                    consumptionUnitRaw = unit.rawValue
                } label: {
                    Text(unit.segmentLabel(l))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(selected ? c.text : c.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule().fill(c.card)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(c.cardAlt, in: Capsule())
        .accessibilityIdentifier("consumption_unit_segment")
    }

    /// Re-expresses whatever is typed right now in the new unit, going through
    /// the stored per-100 value so the round trip cannot drift.
    private func convertFuelFields(to unit: ConsumptionUnit) {
        let lng = lang.language
        for field in [$city, $highway] {
            guard let shown = parsed(field.wrappedValue) else { continue }
            let stored = consumptionUnit.toPer100(shown)
            field.wrappedValue = GarageFormat.fuel(unit.display(fromPer100: stored), lng: lng)
        }
        if let shownPrice = parsed(price) {
            let perLitre = consumptionUnit.priceToPerLitre(shownPrice)
            price = GarageFormat.fuel(unit.displayPrice(fromPerLitre: perLitre), lng: lng)
        }
        // One setting, not two. The trip screen prints fuel volume from this
        // key, so leaving it behind would have a trip say gallons while the
        // garage says litres.
        volumeUnit = unit.volumeUnit.rawValue
    }

    private func priceCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // The row label carries the volume unit and the pill carries the
        // currency: `pricePerLiter` interpolates the app-wide symbol, which is
        // the wrong one now that each vehicle owns its currency.
        // The segment above owns this too: mpg means gallons, so the row
        // reads «Цена за галлон» and the number is converted, not relabelled.
        let unit = GarageFormat.volumeShort(consumptionUnit.volumeUnit.rawValue, lng: l)
        return VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.fuelPriceSection(l), color: c.textSecondary)
            fuelInputRow(
                label: AppStrings.fuelPricePerUnit(l, unit: unit),
                text: $price,
                maxValue: 999,
                c: c
            ) {
                currencyButton()
            }
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func currencyButton() -> some View {
        Button {
            Haptics.tap()
            showCurrencyPicker = true
        } label: {
            HStack(spacing: 3) {
                Text(currencySymbol)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            // Accent, because it is the one part of the pill that is a control.
            .foregroundStyle(AppTheme.accent)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicle_currency_button")
    }

    private func unitLabel(_ text: String, c: AppTheme.Colors) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(c.textTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// Pill-styled inline decimal input. Input filtering, RU comma
    /// normalization and clamping are the retired FuelSettingsCard's
    /// proven logic, verbatim. The trailing element is a view rather than a
    /// string because the price row's unit is the currency BUTTON.
    private func fuelInputRow<Trailing: View>(
        label: String,
        text: Binding<String>,
        maxValue: Double,
        c: AppTheme.Colors,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let lng = lang.language
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
                            text.wrappedValue = GarageFormat.fuel(maxValue, lng: lng)
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

                trailing()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Privacy

    private func privacyCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.privacySection(l), color: c.textSecondary)
            toggleRow(
                AppStrings.showVehicleToggle(l),
                isOn: $visibleToOthers,
                c: c,
                identifier: "vehicle_visible_toggle"
            )
            Text(AppStrings.showVehicleHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    private func toggleRow(
        _ title: String,
        isOn: Binding<Bool>,
        c: AppTheme.Colors,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(c.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(AppTheme.accent)
                .accessibilityIdentifier(identifier)
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
        .accessibilityIdentifier("vehicle_form_save")
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        // The bar is inset ABOVE the home indicator, so a material that stops at
        // its own frame leaves a strip of bare sheet under it — the last row of
        // the form then scrolls through a gap instead of under the bar.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // A type that carries no plate stores none: switching a car to a bicycle
        // must not leave the number behind in the database. `updateVehicleIdentity`
        // enforces this too; `addVehicle` writes what it is handed.
        let plateToStore = selectedType.hasPlate ? VehiclePlate.normalized(plate) : ""
        let showPlate = selectedType.hasPlate && plateVisible

        switch mode {
        case .add:
            let newId = settings.addVehicle(
                name: trimmed,
                emoji: selectedAvatar,
                avatarStyle: selectedAvatarStyle,
                type: selectedType,
                plate: plateToStore,
                plateVisible: showPlate,
                visibleToOthers: visibleToOthers
            )
            if selectedType.burnsFuel {
                let defaults = Vehicle()
                let cityVal = storedConsumption(city) ?? defaults.cityConsumption
                let highwayVal = storedConsumption(highway) ?? defaults.highwayConsumption
                let priceVal = storedPrice(price) ?? defaults.fuelPrice
                if cityVal != defaults.cityConsumption
                    || highwayVal != defaults.highwayConsumption
                    || priceVal != defaults.fuelPrice {
                    settings.updateVehicleFuel(id: newId, city: cityVal, highway: highwayVal, price: priceVal)
                }
                // Written even when it matches today's app-wide symbol.
                // `addVehicle` leaves the column NULL, and NULL reads back as
                // whatever the app-wide currency IS at read time — so skipping
                // the write would leave this vehicle drifting behind the units
                // card instead of keeping the currency the form showed.
                settings.updateVehicleCurrency(id: newId, symbol: currencySymbol)
            }
            settings.selectVehicle(id: newId)

        case .edit(let id):
            guard let original = editedVehicle else { break }
            // One write for the whole identity half, so a type + plate + name
            // change costs one sync operation instead of three.
            let identityChanged = trimmed != original.name
                || selectedAvatar != original.avatarEmoji
                // Without this, changing only the silhouette saves nothing —
                // the colour string is identical and the form closes as if the
                // choice had been taken.
                || selectedAvatarStyle != original.avatarStyle
                || selectedType != original.type
                || plateToStore != original.plate
                || showPlate != original.plateVisible
                || visibleToOthers != original.visibleToOthers
            if identityChanged {
                settings.updateVehicleIdentity(
                    id: id,
                    name: trimmed,
                    emoji: selectedAvatar,
                    type: selectedType,
                    plate: plateToStore,
                    plateVisible: showPlate,
                    visibleToOthers: visibleToOthers,
                    avatarStyle: selectedAvatarStyle
                )
            }
            // Fuel figures belong to a type that burns fuel; a vehicle turned
            // into a bicycle keeps whatever it had rather than being rewritten.
            if selectedType.burnsFuel {
                if city != initialCity || highway != initialHighway || price != initialPrice {
                    settings.updateVehicleFuel(
                        id: id,
                        city: city != initialCity ? (storedConsumption(city) ?? original.cityConsumption) : original.cityConsumption,
                        highway: highway != initialHighway ? (storedConsumption(highway) ?? original.highwayConsumption) : original.highwayConsumption,
                        price: price != initialPrice ? (storedPrice(price) ?? original.fuelPrice) : original.fuelPrice
                    )
                }
                if currencySymbol != original.fuelCurrency {
                    settings.updateVehicleCurrency(id: id, symbol: currencySymbol)
                }
            }
        }

        Haptics.success()
        dismiss()
    }

    private func parsed(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// A consumption field as it must be STORED: litres per 100 km, whatever
    /// dialect the field was typed in.
    private func storedConsumption(_ text: String) -> Double? {
        parsed(text).map { consumptionUnit.toPer100($0) }
    }

    /// A price field as it must be STORED: per litre, whatever the field said.
    private func storedPrice(_ text: String) -> Double? {
        parsed(text).map { consumptionUnit.priceToPerLitre($0) }
    }

    // MARK: - Helpers

    private var consumptionUnit: ConsumptionUnit {
        ConsumptionUnit(rawValue: consumptionUnitRaw) ?? .per100
    }

    private func consumptionUnitLabel(_ l: LanguageManager.Language) -> String {
        consumptionUnit.valueUnit(
            volumeRaw: volumeUnit, distanceRaw: distanceUnit, lng: l)
    }
}
