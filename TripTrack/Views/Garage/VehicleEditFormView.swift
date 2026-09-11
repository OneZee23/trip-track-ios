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
    /// Пробег с приборки, строкой — поле ввода. Пустая строка = не задан.
    @State private var manualOdometer: String = ""
    // Паспорт (0.6.4). Марка и модель — строки, а не идентификаторы каталога:
    // справочник заведомо неполон, и свободный ввод обязан оставаться
    // полноправным, а не запасным путём.
    @State private var make: String
    @State private var carModel: String
    @State private var yearText: String
    @State private var bodyType: String
    @State private var about: String
    @State private var showCatalog = false
    @State private var showPrivacy = false
    @State private var confirmSell = false
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
    /// Пробег с приборки — тоже строкой: см. комментарий в `save()`.
    @State private var initialManualOdometer: String

    /// Единица ЧЕЛОВЕКА — ею подписаны расстояния поездок этой машины, её
    /// рекорды и «до уровня». Числа с ПРИБОРКИ (пробег, расход, цена) идут не
    /// ею, а `vehicleDistanceUnit` ниже.
    @Environment(\.distanceUnit) private var distanceUnit

    /// В чём показывает приборка этой машины. `@State`, а не чтение снимка:
    /// выбор меняется прямо в форме, и поля обязаны перепечататься под него в
    /// ту же секунду.
    @State private var dashboardUnits: DashboardUnits

    /// Лист выбора приборки. Свой (`SettingsOptionPicker`), а не `Menu` и не
    /// `.confirmationDialog`: системные модалки в этом приложении не ставятся
    /// вовсе — см. раздел «Dialogs» в CLAUDE.md.
    @State private var showDashboardPicker = false

    /// Snapshot of the edited vehicle taken at init — used for
    /// changed-only saves so SyncEnqueuer isn't churned needlessly.
    private let editedVehicle: Vehicle?

    private static let avatarColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(mode: Mode) {
        self.mode = mode
        let lng = LanguageManager.currentLanguage
        // Единица ЧЕЛОВЕКА: `@Environment(\.distanceUnit)` в `init` ещё не
        // существует, а `DistanceUnit.current` — тот же самый выбор из того же
        // хранилища (умолчание окружения считается по нему же).
        let appDistance = DistanceUnit.current

        if case .edit(let id) = mode,
           let vehicle = SettingsManager.shared.vehicles.first(where: { $0.id == id }) {
            editedVehicle = vehicle
            // Поля паспорта заполняются В ЕДИНИЦЕ ПРИБОРКИ, а не человека:
            // всё, что тут вводят, списывают с панели этой машины.
            let shownDistance = vehicle.dashboardUnit(app: appDistance)
            let shownUnit = ConsumptionUnit.forDashboard(shownDistance)
            _dashboardUnits = State(initialValue: vehicle.dashboardUnits)
            _name = State(initialValue: vehicle.name)
            _selectedType = State(initialValue: vehicle.type)
            _plate = State(initialValue: vehicle.plate)
            _make = State(initialValue: vehicle.make)
            _carModel = State(initialValue: vehicle.model)
            _yearText = State(initialValue: vehicle.year > 0 ? String(vehicle.year) : "")
            _bodyType = State(initialValue: vehicle.bodyType)
            _about = State(initialValue: vehicle.about)
            _plateVisible = State(initialValue: vehicle.plateVisible)
            // Пустая строка, если реальный пробег ещё не вводили — так поле
            // показывает «—», а не выдуманный ноль.
            //
            // Число — В ЕДИНИЦЕ ПРИБОРКИ. Это единственное место во всём
            // приложении, где человек ВВОДИТ расстояние, и ради него половина
            // версии: у машины с мильной приборкой до 0.6.7 не было способа
            // ввести свой пробег — поле требовало пересчитать его в уме, — а с
            // единицей ЧЕЛОВЕКА километровая панель американца разбиралась бы
            // как мили и уезжала в базу увеличенной в 1.609 раза.
            _manualOdometer = State(initialValue:
                OdometerField.fieldText(km: vehicle.manualOdometerKm, unit: shownDistance))
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
            // У новой машины приборки ещё нет — «как в приложении», ровно как
            // у всех заведённых до 0.6.7.
            _dashboardUnits = State(initialValue: defaults.dashboardUnits)
            let shownUnit = ConsumptionUnit.forDashboard(
                defaults.dashboardUnit(app: appDistance))
            _name = State(initialValue: "")
            _selectedType = State(initialValue: .car)
            _plate = State(initialValue: "")
            _make = State(initialValue: "")
            _carModel = State(initialValue: "")
            _yearText = State(initialValue: "")
            _bodyType = State(initialValue: "")
            _about = State(initialValue: "")
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
        _initialManualOdometer = State(initialValue: _manualOdometer.wrappedValue)
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
                    passportCard(c: c, l: l)
                    if selectedType.hasPlate {
                        plateCard(c: c, l: l)
                    }
                    avatarCard(c: c, l: l)
                    if selectedType.burnsFuel {
                        fuelCard(c: c, l: l)
                        priceCard(c: c, l: l)
                    }
                    // Только у СУЩЕСТВУЮЩЕЙ машины. В режиме добавления экран
                    // «Кого пускать» получал `UUID()`, который не совпадает ни
                    // с одной строкой: он ничего не читал и ничего не сохранял,
                    // то есть человек на самом первом запуске прятал номер и
                    // карту, жал «Готово», и всё это выбрасывалось молча.
                    // Машина создаётся одним тапом — настройки в двух тапах
                    // после неё, и они работают.
                    if editedVehicle != nil {
                        privacyCard(c: c, l: l)
                    }
                    if let vehicle = editedVehicle {
                        mileageCard(vehicle, c: c, l: l)
                        // Самой последней: продажа замораживает биографию, и
                        // до неё человек должен доскроллить, а не наткнуться.
                        soldCard(vehicle, c: c, l: l)
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
        // Смена приборки ПЕРЕПЕЧАТЫВАЕТ набранное, а не переподписывает его:
        // 142 000 на километровой панели — это 88 235 на мильной, одна и та же
        // машина. Переподписанное поле сохранилось бы как другое число.
        .onChange(of: dashboardUnits) { old, new in
            convertUnitFields(from: old, to: new)
        }
        .sheet(isPresented: $showCurrencyPicker) {
            FuelCurrencyPickerSheet(selectedSymbol: $currencySymbol)
                .environmentObject(lang)
                // A sheet over a sheet does not inherit the theme override, and
                // `scheme` is already the resolved one.
                .preferredColorScheme(scheme)
        }
        .sheet(isPresented: $showDashboardPicker) {
            dashboardUnitsPicker(lang.language)
                .environmentObject(lang)
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

    /// «Продана» — редкое и почти необратимое действие, поэтому оно лежит в
    /// конце формы редактирования, а не в списке «…» на экране машины.
    ///
    /// Продажа значит, что владелец сменился: записывать на такую машину новые
    /// поездки нельзя — это была бы чужая дорога в твоём паспорте. Поэтому она
    /// же снимается с активной, и об этом сказано ДО нажатия, а не после.
    @ViewBuilder
    private func soldCard(_ vehicle: Vehicle, c: AppTheme.Colors,
                          l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.vehicleStateSection(l), color: c.textSecondary)
            Button {
                Haptics.tap()
                if vehicle.isSold {
                    // Отмена продажи ничего не разрушает — подтверждать нечего.
                    settings.setVehicleSold(id: vehicle.id, soldAt: nil)
                } else {
                    confirmSell = true
                }
            } label: {
                HStack(spacing: 10) {
                    Text(vehicle.isSold ? AppStrings.vehicleUnsell(l) : AppStrings.vehicleMarkSold(l))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(vehicle.isSold ? c.text : AppTheme.accent)
                    Spacer(minLength: 8)
                    Image(systemName: vehicle.isSold ? "arrow.uturn.backward" : "hand.wave")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(vehicle.isSold ? AppStrings.vehicleSoldHintOn(l) : AppStrings.vehicleSoldHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        // Домовой диалог, не системный — см. «Dialogs» в CLAUDE.md.
        .appConfirm(
            isPresented: $confirmSell,
            title: AppStrings.vehicleSellConfirmTitle(l),
            message: AppStrings.vehicleSellConfirmBody(l),
            actions: [
                AppDialogAction(AppStrings.vehicleMarkSold(l), kind: .destructive) {
                    settings.setVehicleSold(id: vehicle.id, soldAt: Date())
                }
            ],
            cancelTitle: AppStrings.cancel(l)
        )
    }

    // MARK: - Паспорт: марка, модель, год (0.6.4)

    /// Строка «Марка и модель» ведёт в справочник, год набирается руками.
    ///
    /// Значение стоит ПОД ярлыком, а не справа от него: в канон это пришло
    /// после того, как выяснилось, что справа ему остаётся 120pt, а сто две
    /// записи справочника из пятисот двадцати одной длиннее — «Land Rover
    /// Range Rover Evoque» не помещается никак.
    private func passportCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.vehicleWhatSection(l), color: c.textSecondary)

            Button { showCatalog = true } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.vehicleMakeModel(l))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                        Text(passportTitle(l))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(passportTitleIsEmpty ? c.textTertiary : c.text)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Text(AppStrings.vehicleYear(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                Spacer(minLength: 8)
                TextField(AppStrings.vehicleNotSet(l), text: $yearText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .tint(AppTheme.accent)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 72)
                    .onChange(of: yearText) { _, v in
                        let digits = v.filter(\.isNumber)
                        if digits != v { yearText = String(digits.prefix(4)) }
                        else if digits.count > 4 { yearText = String(digits.prefix(4)) }
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))

            // Одна строка, а не многострочный редактор: форма поля и есть
            // обещание объёма. Дай текстовое полотно — получишь бортжурнал,
            // которого мы сознательно не делаем.
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.vehicleAbout(l))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                TextField(AppStrings.vehicleAboutPlaceholder(l), text: $about, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(c.text)
                    .tint(AppTheme.accent)
                    .lineLimit(1...3)
                    .onChange(of: about) { _, v in
                        if v.count > 140 { about = String(v.prefix(140)) }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44, alignment: .leading)
            .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        .sheet(isPresented: $showPrivacy) {
            // Форма сама показана шитом, стека под ней нет — поэтому вложенный
            // шит, а не push. Экран приватности самодостаточен: он пишет на
            // каждое переключение и не требует «Готово».
            // `editedVehicle` здесь всегда есть: карточка, из которой сюда
            // попадают, в режиме добавления не рисуется вовсе.
            VehiclePrivacyView(vehicleId: editedVehicle?.id ?? UUID())
                .environmentObject(lang)
        }
        .sheet(isPresented: $showCatalog) {
            VehicleCatalogPickerView(
                type: selectedType.rawValue,
                initialQuery: make
            ) { pickedMake, pickedModel, pickedBody in
                make = pickedMake
                carModel = pickedModel
                bodyType = pickedBody
                // Силуэт идёт следом за кузовом: выбрал «Polo» — спрайт стал
                // седаном сам. Каталог предлагает, тип решает.
                selectedAvatarStyle = VehicleAvatar.resolveStyle(
                    pickedBody, forType: selectedType.rawValue)
            }
            .environmentObject(lang)
        }
    }

    private var passportTitleIsEmpty: Bool {
        make.isEmpty && carModel.isEmpty
    }

    private func passportTitle(_ l: LanguageManager.Language) -> String {
        let parts = [make, carModel].filter { !$0.isEmpty }
        return parts.isEmpty ? AppStrings.vehicleNotSet(l) : parts.joined(separator: " ")
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
                                .padding(.horizontal, 5)
                                .padding(.vertical, 7)
                        }
                        // The tile is a picture; VoiceOver has nothing to read
                        // without this and announces seven identical buttons.
                        .accessibilityLabel(AppStrings.avatarStyleName(l, style: style))
                        .accessibilityAddTraits(selectedStyle == style ? [.isSelected] : [])
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
                .frame(width: 168, height: 106)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
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
                    swatchButton(isSelected: selectedAvatar == legacy,
                                 label: legacy, c: c) {
                        selectedAvatar = legacy
                    } fill: {
                        Circle()
                            .fill(c.cardAlt)
                            .overlay(Text(legacy).font(.system(size: 17)))
                    }
                }
                ForEach(VehicleAvatar.colors, id: \.self) { color in
                    let rgb = VehicleAvatar.swatch(color)
                    swatchButton(isSelected: selectedColor == color && VehicleAvatar.isAsset(selectedAvatar),
                                 label: AppStrings.avatarColorName(lang.language, color: color),
                                 c: c) {
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
        label: String,
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
        // Кружок — это только цвет: без имени VoiceOver читает восемь
        // одинаковых кнопок, а три из них ещё и соседние оттенки серого.
        .accessibilityLabel(label)
        // Без этого признака непонятно, какой цвет сейчас выбран: кольцо
        // вокруг кружка — чисто зрительная подсказка.
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                // Taller since the sprites lost their empty margin: the car
                // fills the tile now instead of floating in a third of it,
                // which is what made them look small in a picker whose whole
                // job is comparing them.
                .frame(height: 68)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(
                            colors: [AppTheme.spritePlateTop, AppTheme.spritePlateBottom],
                            startPoint: .top, endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? AppTheme.accent.opacity(0.16) : .clear)
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
        // normal figure the moment the dashboard says miles.
        let ceiling: Double = consumptionUnit.inputCeiling
        return VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.fuelSectionLabel(l), color: c.textSecondary)
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

    /// Перепечатать всё, что набрано, в новой единице приборки.
    ///
    /// Именно ПЕРЕПЕЧАТАТЬ, а не переподписать: диалекты расхода идут в разные
    /// стороны (9,1 л/100 км — это 25,8 mpg), и смена подписи превратила бы
    /// экономичную машину в прожорливую одним нажатием. Пробег с панели тоже
    /// перепечатывается: 142 000 на километровой панели — это те же 88 235 на
    /// мильной, одна и та же машина.
    ///
    /// Круг идёт через ХРАНИМОЕ значение (литры на сотню километров, цена за
    /// литр, километры пробега), а не из показанного в показанное: иначе
    /// каждое переключение считало бы от уже округлённого числа и уводило его
    /// дальше. Совсем без сдвига не обойтись — поле показывает одну десятую, а
    /// пробег целые единицы, — но сдвиг тут ровно тот же, что при наборе того
    /// же числа руками, и не накапливается.
    ///
    /// Глобальных настроек эта функция не трогает НИ ОДНОЙ — и это половина
    /// смысла 0.6.7. До неё здесь стоял `SettingsManager.setVolumeUnit`, и
    /// американка, заведённая в российском гараже, переводила в галлоны весь
    /// аккаунт: настройка уезжала на сервер и возвращалась на второй телефон.
    private func convertUnitFields(from old: DashboardUnits, to new: DashboardUnits) {
        let lng = lang.language
        let oldDistance = old.resolved(app: distanceUnit)
        let newDistance = new.resolved(app: distanceUnit)
        guard oldDistance != newDistance else { return }

        let oldUnit = ConsumptionUnit.forDashboard(oldDistance)
        let newUnit = ConsumptionUnit.forDashboard(newDistance)

        for field in [$city, $highway] {
            guard let shown = parsed(field.wrappedValue) else { continue }
            let stored = oldUnit.toPer100(shown)
            field.wrappedValue = GarageFormat.fuel(newUnit.display(fromPer100: stored), lng: lng)
        }
        if let shownPrice = parsed(price) {
            let perLitre = oldUnit.priceToPerLitre(shownPrice)
            price = GarageFormat.fuel(newUnit.displayPrice(fromPerLitre: perLitre), lng: lng)
        }
        if let km = OdometerField.storedKm(manualOdometer, unit: oldDistance) {
            manualOdometer = OdometerField.fieldText(km: km, unit: newDistance)
        }
    }

    private func priceCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // The row label carries the volume unit and the pill carries the
        // currency: `pricePerLiter` interpolates the app-wide symbol, which is
        // the wrong one now that each vehicle owns its currency.
        //
        // Обе половины подписи помашинные, и разъехаться им нельзя: валюта у
        // машины своя с 0.6.4, объём стал своим в 0.6.7 (мильная приборка —
        // галлоны), а «рубли за галлон» — подпись, у которой нет числа. Число
        // при этом переводится, а не переподписывается.
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

    /// Строка-переход вместо трёх тумблеров прямо в форме.
    ///
    /// Канон 0.6.4 собирает все четыре оси на одном экране, и это не вкусовщина:
    /// пока тумблеры жили здесь, экран «Приватность машины» был недостижим ни
    /// из одного места приложения, а флаги имели два источника правды.
    private func privacyCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.privacySection(l), color: c.textSecondary)
            Button {
                Haptics.tap()
                showPrivacy = true
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.vehicleWhoSees(l))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(c.text)
                        Text(AppStrings.vehiclePrivacyRowHint(l))
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                // Здесь СОЗНАТЕЛЬНО треканное число, а не `displayOdometerKm`:
                // подпись под ним говорит «начисляется автоматически по
                // поездкам», и показывать под ней введённое руками значило бы
                // подписать чужое число чужим объяснением. Поле ручного
                // пробега стоит отдельной строкой ниже.
                Text(trackedOdometer(vehicle, l).value)
                    .font(.system(size: 22, weight: .heavy).monospacedDigit())
                    .foregroundStyle(c.text)
                Text(trackedOdometer(vehicle, l).unit)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
            }
            Text(AppStrings.mileageAutoHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)

            Divider().padding(.vertical, 4)

            dashboardUnitsRow(c: c, l: l)

            // Реальный пробег с панели. Отдельно от треканного и НЕ влияет на
            // уровень: уровень — награда за записанные поездки, а не за цифру
            // с клавиатуры.
            HStack(spacing: 10) {
                Text(AppStrings.odometerEditTitle(l))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    TextField("—", text: Binding(
                        get: { manualOdometer },
                        // Именно ASCII-цифры, а не `isNumber`: тот пропускает
                        // арабо-индийские цифры и «½», а `Double(_:)` их потом
                        // отвергает — и сохранение молча стирало бы значение.
                        set: { manualOdometer = String($0.unicodeScalars
                            .filter { CharacterSet.decimalDigits.contains($0) && $0.isASCII }
                            .prefix(7)) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                    .tint(AppTheme.accent)
                    .frame(width: 80)
                    .accessibilityIdentifier("vehicle_manual_odometer")
                    Text(manualOdometerUnit(l))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(c.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(c.cardAlt, in: RoundedRectangle(cornerRadius: 10))
            }

            Text(AppStrings.odometerEditHint(l))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            dashboardUnitsFieldHint(c: c, l: l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
    }

    // MARK: - Приборка

    /// Строка «Приборка» — непосредственно НАД полем ручного пробега, рядом с
    /// тем, чем она командует.
    ///
    /// Не в настройках приложения: та отвечает на «в чём я мыслю», эта — на
    /// «что написано вот на ЭТОЙ панели». У человека с тойотой и мустангом
    /// ответы разные, и одной настройкой на аккаунт их не покрыть — ровно эту
    /// дыру закрывает версия.
    ///
    /// Живёт внутри карточки пробега, то есть только у СУЩЕСТВУЮЩЕЙ машины:
    /// при заведении вопрос не задаётся. В девяти случаях из десяти приборка
    /// совпадает с приложением, и лишний вопрос на первом экране стоит дороже,
    /// чем две секунды правки потом.
    private func dashboardUnitsRow(
        c: AppTheme.Colors, l: LanguageManager.Language
    ) -> some View {
        Button {
            Haptics.tap()
            showDashboardPicker = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.vehicleDashboardTitle(l))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(c.text)
                    // Подзаголовок — он и есть ответ на «это что, ещё одни
                    // единицы?». Без него строка читается как дубль настройки
                    // приложения.
                    Text(AppStrings.vehicleDashboardSubtitle(l))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(dashboardUnits.label(l, burnsFuel: selectedType.burnsFuel))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                // Шеврон, потому что строка ОТКРЫВАЕТ лист: «если нажатие
                // что-то открывает — это видно» (CLAUDE.md).
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(c.textTertiary)
            }
            .contentShape(Rectangle())
        }
        // Не голый `.plain`: отклик обязан быть в момент КАСАНИЯ, а не в
        // момент, когда откроется лист.
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("vehicle_dashboard_units")
    }

    /// Живая строка под полем: в чём число сейчас ждут — и как это поменять.
    ///
    /// Нажимается вся строка, подсвечено одно слово: объяснение и действие тут
    /// одно и то же — «единица не та». Ведёт в тот же лист, что строка выше:
    /// два входа, одна дверь. Второй вход нужен потому, что смотрят сюда в
    /// другой момент — не выбирая настройку, а сверяя поле с панелью, — и
    /// искать наверху объяснение того, что видишь внизу, человек не станет.
    ///
    /// Имя единицы берётся `resolvedLabel`: «Как в приложении» здесь не
    /// печатается никогда — на вопрос «мили или километры я набираю» это не
    /// ответ.
    private func dashboardUnitsFieldHint(
        c: AppTheme.Colors, l: LanguageManager.Language
    ) -> some View {
        let units = dashboardUnits.resolvedLabel(
            l, app: distanceUnit, burnsFuel: selectedType.burnsFuel)
        return Button {
            Haptics.tap()
            showDashboardPicker = true
        } label: {
            (Text(AppStrings.dashboardUnitsFieldHint(l, units: units))
                .foregroundStyle(c.textTertiary)
             + Text(" ")
             + Text(AppStrings.dashboardUnitsChange(l))
                .foregroundStyle(AppTheme.accent))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("vehicle_dashboard_units_hint")
    }

    /// Лист выбора — домашний `SettingsOptionPicker` в `contentSizedSheet`,
    /// тот же, что носят «Единицы», «Язык» и «Тема».
    ///
    /// Выбор ложится в `@State`, а не сразу в базу: сохраняет его `save()`
    /// вместе с остальной формой, а `.onChange(of: dashboardUnits)` тут же
    /// перепечатывает набранные числа. Писать отсюда прямо в
    /// `setDashboardUnits` значило бы сохранить единицу у человека, который
    /// потом закрыл форму крестиком, — приборка уехала бы на сервер, а числа,
    /// разобранные ею, нет.
    private func dashboardUnitsPicker(_ l: LanguageManager.Language) -> some View {
        SettingsOptionPicker(
            title: AppStrings.vehicleDashboardTitle(l),
            // `allCases`, а не три перечисленных значения: четвёртая единица
            // (британский микс) появится в списке сама, а не окажется
            // выбором, до которого в интерфейсе не дойти.
            options: DashboardUnits.allCases,
            selection: dashboardUnits,
            footnote: AppStrings.dashboardUnitsPickerFootnote(l),
            badge: { $0.badge(l, app: distanceUnit) },
            label: { $0.label(l, burnsFuel: selectedType.burnsFuel) },
            onSelect: { dashboardUnits = $0 },
            accessibilityPrefix: "vehicle_dashboard_units"
        )
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
            // Паспорт пишется сразу после создания: у только что заведённой
            // машины это единственное, что уже можно заполнить, — биография
            // появится сама после первой поездки.
            settings.updateVehiclePassport(
                id: newId, make: make, model: carModel,
                year: Int(yearText) ?? 0, bodyType: bodyType, about: about
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
            // Приборка пишется отдельной дверью — той же, что у правки:
            // `addVehicle` о ней не знает, а «как в приложении» и так стоит
            // умолчанием, поэтому лишней записи на обычном пути нет.
            if dashboardUnits != Vehicle().dashboardUnits {
                settings.setDashboardUnits(vehicleId: newId, dashboardUnits)
            }
            settings.selectVehicle(id: newId)

        case .edit(let id):
            guard let original = editedVehicle else { break }
            // Приборка — первой: следом идут пробег и расход, и они уже
            // разобраны в ЕЁ единице. Порядок здесь не косметика — пул,
            // приехавший между двумя записями, увидел бы числа, разобранные
            // одной единицей, при ещё старом значении поля.
            if dashboardUnits != original.dashboardUnits {
                settings.setDashboardUnits(vehicleId: id, dashboardUnits)
            }
            // Реальный пробег живёт отдельной записью: он не часть «личности»
            // машины и не должен тащить за собой её sync-операцию, когда
            // менялось только число на приборке.
            // Сравниваются СТРОКИ, а не километры, и это не придирка.
            // У человека с милями путь «в базе км → в поле мили → обратно в
            // км» не сходится сам с собой на единицы километров: 100 000 км
            // показываются как 62 137 миль, а 62 137 миль — это 100 000,3 км.
            // Сравнение чисел объявляло бы пробег изменившимся при КАЖДОМ
            // сохранении формы, переписывало бы его и ставило лишнюю операцию
            // в очередь синка — ровно та ловушка, что уже описана выше у
            // полей расхода (`initialCity`).
            if manualOdometer.trimmingCharacters(in: .whitespaces) != initialManualOdometer {
                settings.setManualOdometer(vehicleId: id, km: storedManualOdometerKm)
            }
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
            settings.updateVehiclePassport(
                id: id, make: make, model: carModel,
                year: Int(yearText) ?? 0, bodyType: bodyType, about: about
            )
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

    // MARK: - Пробег

    /// Треканный пробег — число и подпись. В единице ПРИБОРКИ: он стоит в
    /// одном кадре с реальным и вычитается из него глазами, а две разные
    /// единицы в одной арифметике — это неверный ответ на экране.
    ///
    /// Одометр хранится в километрах и в 0.6.7 в метры не мигрирует (против
    /// него уже записаны уровни машин в базе), поэтому вход у `Measure`
    /// километровый и назван вслух.
    private func trackedOdometer(
        _ vehicle: Vehicle, _ l: LanguageManager.Language
    ) -> Measure.Parts {
        Measure.distanceParts(km: vehicle.odometerKm, unit: vehicleDistanceUnit, lang: l)
    }

    /// Подпись у поля ввода. Склоняется по тому, что в поле НАПЕЧАТАНО:
    /// «1 миля», но «12 миль». Пустое поле подписывается как сотня — это
    /// множественное число во всех тринадцати языках.
    private func manualOdometerUnit(_ l: LanguageManager.Language) -> String {
        let shown = Double(manualOdometer.trimmingCharacters(in: .whitespaces)) ?? 100
        return AppStrings.unitDistanceShort(
            l, unit: vehicleDistanceUnit, value: shown, fractionDigits: 0)
    }

    /// То, что напечатано в поле, → километры для хранения. Разбор живёт в
    /// `OdometerField` чистой функцией: это единственный вход, где ошибка с
    /// единицей попадает в БАЗУ, и держать его обязан тест, а не открытая
    /// форма на телефоне.
    private var storedManualOdometerKm: Double? {
        OdometerField.storedKm(manualOdometer, unit: vehicleDistanceUnit)
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

    // MARK: - Единицы

    /// В чём показывать и разбирать числа С ПРИБОРКИ: пробег, расход, цену.
    ///
    /// Не `distanceUnit`: тот — единица ЧЕЛОВЕКА, и ею подписаны расстояния
    /// поездок, рекорды и «до уровня». Здесь же всё, что человек списывает с
    /// панели своей машины, и ответ на вопрос «если он сейчас глянет на
    /// панель, он увидит ровно это число?».
    private var vehicleDistanceUnit: DistanceUnit {
        dashboardUnits.resolved(app: distanceUnit)
    }

    /// Диалект расхода выводится из приборки, отдельной галочки у него нет —
    /// см. `ConsumptionUnit`.
    private var consumptionUnit: ConsumptionUnit {
        ConsumptionUnit.forDashboard(vehicleDistanceUnit)
    }

    private func consumptionUnitLabel(_ l: LanguageManager.Language) -> String {
        consumptionUnit.valueUnit(l)
    }
}
