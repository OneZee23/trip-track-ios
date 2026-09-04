import SwiftUI
import MapKit

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
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var showEditForm = false
    @State private var showPhotos = false
    @State private var showTrips = false
    @State private var showMap = false
    @State private var openTripId: UUID?
    /// Главная фотография машины — она же герой экрана, как в каноне.
    @State private var mainPhoto: VehiclePhoto?

    /// Биография машины: три числа и рекорды, посчитанные из ЕЁ поездок.
    ///
    /// Считается один раз в `.task` и держится здесь, а не пересчитывается в
    /// `body`: у человека с сотнями поездок это разбор полилиний на каждую
    /// перерисовку экрана.
    @State private var passport: Passport?

    private struct Passport {
        var tripCount = 0
        var regionCount = 0
        var daysOnRoad = 0
        var agg: MeAggregates?
        /// Первые строки списка «Поездки этой машины». Держим ровно столько,
        /// сколько показываем: полный список — отдельный экран.
        var recent: [Trip] = []
        /// Полилинии для мини-карты «Где была». Хранятся упрощёнными
        /// (`previewCoordinates`) — рисовать полный трек в карточке 130pt
        /// высотой незачем.
        var routes: [[CLLocationCoordinate2D]] = []
        var cityCount = 0
        /// «Выше всего поднималась» — рекорд из `Trip.elevation`. В
        /// `MeAggregates` его нет, поэтому считается здесь же, по тем же
        /// поездкам, чтобы не заводить второй проход по массиву.
        var highest: (title: String, meters: Double)?
    }
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
        vehicleId == settings.activeRecordableVehicleId
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
        // Не просто «не активная», а «может стать активной»: у проданной или
        // архивной этот пункт молча уводил в никуда — выбор записывался, а
        // потом отфильтровывался обратно, и человек оставался вообще без
        // активной машины, без единого сообщения. В гараже такая же кнопка
        // уже была под охраной, и два экрана расходились.
        if !isMain, let vehicle, !vehicle.isSold, !vehicle.isArchived {
            items.append(
                .init(title: AppStrings.makeMainVehicle(l), systemImage: "star") {
                    run { settings.selectVehicle(id: vehicleId) }
                }
            )
        }
        // Архив — обратимое действие, поэтому без подтверждения. Проданную
        // машину из архива не поднимаем: снятие «продана» это отдельный шаг.
        if let vehicle, !vehicle.isSold {
            items.append(
                .init(title: vehicle.isArchived
                      ? AppStrings.vehicleUnarchiveAction(l)
                      : AppStrings.vehicleArchiveAction(l),
                      systemImage: vehicle.isArchived ? "tray.and.arrow.up" : "archivebox") {
                    run { settings.setVehicleArchived(id: vehicleId, archived: !vehicle.isArchived) }
                }
            )
        }
        // Продажи здесь НЕТ намеренно. Машину продают раз в несколько лет, а
        // «…» — список на каждый день; редкое и необратимое действие в нём
        // соседствует с обыденным и однажды получает случайный тап.
        // Оно живёт в форме редактирования, куда заходят осознанно.
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
                        // Паспорт (0.6.4): круги теперь внутри шапки, здесь —
                        // строка владельца и рекорды. Всё из поездок ЭТОЙ машины.
                        aboutCard(vehicle, c: c, l: l)
                        odometerCard(vehicle, c: c, l: l)
                        whereWasCard(c: c, l: l)
                        vehicleTrips(c: c, l: l)
                        vehicleRecords(c: c, l: l)
                        // A bicycle pairs with no stereo, so auto-record has
                        // nothing to key off — the rows are absent, not
                        // disabled (canon: hidden means gone).
                        // На проданную и архивную машину не записывается
                        // ничего — значит и предлагать ей автозапись нельзя.
                        // Паспорт проданной машины показывал «Привязать
                        // магнитолу» и «Автозапись · Вкл» прямо под строкой
                        // «Продана в сентябре»: обещание, которое приложение
                        // выполнить уже не может, — воткнёшь магнитолу и
                        // получишь тишину.
                        if vehicle.type.supportsAutoRecord, !vehicle.isSold, !vehicle.isArchived {
                            // Always present, never conditional. It used to
                            // appear only when Bluetooth was off AND
                            // auto-record was armed, which meant its silence
                            // carried two opposite meanings — "all good" and
                            // "nothing is set up" — and the card gave no way
                            // to tell them apart at a glance.
                            recordingSection(c: c, l: l)
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
            .task(id: vehicleId) { await loadPassport() }
            // Машину могли удалить с другого экрана (или синком) прямо сейчас.
            // Раньше `if let vehicle` без `else` оставлял пустой экран без
            // шапки и без единого способа уйти — приходилось убивать приложение.
            .onChange(of: settings.vehicles.count) { _, _ in
                if settings.vehicle(for: vehicleId) == nil { dismiss() }
            }
            // Строка в карточке «Поездки» открывает саму поездку: список, по
            // которому нельзя ткнуть, читается как картинка, а не как список.
            .navigationDestination(item: $openTripId) { id in
                TripDetailView(tripId: id,
                               viewModel: TripsViewModel(tripManager: mapVM.tripManager))
            }
            .navigationDestination(isPresented: $showMap) {
                VehicleMapView(vehicleId: vehicleId, vehicleName: displayName(vehicle, l))
                    .environmentObject(lang)
            }
            .navigationDestination(isPresented: $showTrips) {
                VehicleTripsView(vehicleId: vehicleId, vehicleName: displayName(vehicle, l))
                    .environmentObject(lang)
            }
            .navigationDestination(isPresented: $showPhotos) {
                VehiclePhotosView(vehicleId: vehicleId, vehicleName: displayName(vehicle, l))
                    .environmentObject(lang)
            }
            // Возврат с экрана фотографий обязан обновить героя: человек мог
            // только что сменить главную, и старая на этом экране была бы ложью.
            .onChange(of: showPhotos) { _, open in
                if !open { mainPhoto = VehiclePhotoStore.mainPhoto(of: vehicleId) }
            }
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
            Button {
                Haptics.tap()
                showPhotos = true
            } label: {
                // Канон рисует героем ФОТОГРАФИЮ. Пока её нет — спрайт, но
                // тап ведёт в одно и то же место: «у машины должно быть лицо»
                // — единственное, что мы взяли у drive2 без поворота.
                if let photo = mainPhoto {
                    // Уменьшенная копия, а не оригинал с камеры: герой ровно
                    // 180 точек высотой, и декодировать ради него десять
                    // мегапикселей на каждой отрисовке экрана незачем.
                    VehiclePhotoImage(photo: photo, maxSize: 400)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    VehicleSpritePlate(
                        assetName: vehicle.avatarImageName,
                        fallbackEmoji: vehicle.isPixelAvatar ? nil : vehicle.avatarEmoji,
                        plateSize: heroPlateWidth,
                        cornerRadius: 20
                    )
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text(displayName(vehicle, l))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.6)
                .padding(.top, 16)

            // Модель под именем — как в каноне: заголовок это ИМЯ машины
            // («Полторашка»), а «Volkswagen Polo · 2019 · седан» подпись.
            // Строки нет вовсе, пока паспорт не заполнен: пустая подпись под
            // именем читается как поломка, а не как приглашение.
            if let sub = modelLine(vehicle, l) {
                Text(sub)
                    .font(.system(size: 13))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.horizontal, 8)
            }

            // Состояние машины прямо под моделью: проданная не должна выглядеть
            // как обычная, иначе человек попробует записать на неё поездку.
            if vehicle.isSold {
                Text(AppStrings.vehicleSoldState(l, when: soldWhen(vehicle, l)))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 6)
            }

            if vehicle.hasPlate {
                // The owner always sees their own plate here. `plateVisible`
                // is about OTHER people (see `Vehicle.publicPlate`) — hiding
                // it from the person who typed it in would be theatre.
                VehiclePlateChip(plate: vehicle.plate)
                    .padding(.top, 8)
            }

            // Канон рисует пилюлю, а не полосу. Полосу заменяем, но оставляем
            // её роль входа: «Уровень машины» иначе становится недостижим.
            Button {
                Haptics.tap()
                showLevelInfo = true
            } label: {
                LvlPill(level: vehicle.level, rankTitle: "")
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            // Круги живут ВНУТРИ шапки, как в каноне, а не отдельной карточкой:
            // это те же три числа про эту машину, и разрывать их рамкой значит
            // делать из одной мысли две.
            Divider().overlay(c.border).padding(.top, 18)
            passportCircles(c: c, l: l).padding(.top, 14)

            // Только стаж, без второй «•••».
            //
            // Канон рисует три точки здесь, но в этом приложении они уже стоят
            // в навбаре и открывают ТОТ ЖЕ список действий. Две одинаковые
            // кнопки на одном экране — это не следование макету, а вопрос
            // «а эта чем отличается?». Осталась та, что выше: она на месте на
            // всех экранах и доступна, куда бы ни прокрутили.
            //
            // Заодно ушла пустота под строкой: кнопка была 32pt высотой при
            // тексте в 13, и разница дорисовывалась воздухом.
            Divider().overlay(c.border).padding(.top, 14)
            Text(AppStrings.inGarageSince(
                l, when: StatsPeriodFormat.monthYearGenitive(vehicle.createdAt, l)))
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        // Сверху 22, снизу 16: карточка начинается крупным спрайтом, а
        // кончается строкой в 11pt, и одинаковый отступ с обеих сторон
        // оставлял под ней заметно больше воздуха, чем над картинкой.
        .padding(.top, 22)
        .padding(.bottom, 16)
        .surfaceCard(cornerRadius: 20)
    }

    /// Sized off the screen rather than pinned, so the car stays the biggest
    /// thing on the card on an SE and does not swallow the fold on a Max.
    private func soldWhen(_ v: Vehicle, _ l: LanguageManager.Language) -> String {
        guard let d = v.soldAt else { return "" }
        // Предложный, а не родительный: строка читается «Продана в сентябре»,
        // и родительный дал бы «в сентября». Для языков без падежей функция
        // возвращает то же, что и раньше.
        return StatsPeriodFormat.monthYearPrepositional(d, l)
    }

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

    /// Вторая строка одометра: сколько из показанного числа приложение видело
    /// само, и сколько прошло мимо записи. Ради этого разрыва одометр и
    /// раздвоили — он и есть повод дотрекать.
    @ViewBuilder
    private func odometerBreakdown(
        _ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language
    ) -> some View {
        if vehicle.manualOdometerKm != nil {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.odometerTrackedLine(
                    l, km: "\(GarageFormat.odometer(vehicle.odometerKm, lng: l)) \(AppStrings.km(l))"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                if let gap = vehicle.untrackedKm {
                    Text(AppStrings.odometerUntrackedLine(
                        l, km: "\(GarageFormat.odometer(gap, lng: l)) \(AppStrings.km(l))"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("vehicle_odometer_breakdown")
        }
    }

    /// Одометр одной карточкой с крупным числом — как в каноне. Раньше это
    /// была сетка из двух плиток (пробег + расход), и пробег в ней читался
    /// наравне с расходом, хотя он и есть биография машины. Расход никуда не
    /// делся: он живёт в топливной секции ниже, где ему и место.
    private func odometerCard(_ vehicle: Vehicle, c: AppTheme.Colors,
                              l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(GarageFormat.odometer(vehicle.displayOdometerKm, lng: l))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(c.text)
                Text(AppStrings.km(l))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textTertiary)
            }
            odometerBreakdown(vehicle, c: c, l: l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfaceCard(cornerRadius: 16)
        // Одометр открывает ввод реального пробега — того самого числа, ради
        // которого он и показан двумя строками. Раньше карточка не делала
        // ничего, а поле пряталось за «…» → «Редактировать» → прокрутить.
        .contentShape(Rectangle())
        .onTapGesture { Haptics.tap(); showEditForm = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(AppStrings.odometerLabel(l))
    }

    private func statGrid(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // No measured consumption exists — mean of city/highway settings (fork F10).
        // Averaged BEFORE conversion: mpg is a reciprocal, so the mean of
        // two mpg figures is not the mpg of the mean consumption.
        let avg = shownConsumption((vehicle.cityConsumption + vehicle.highwayConsumption) / 2)

        return HStack(spacing: 10) {
            statCard(
                // Главный — реальный, если введён (решение владельца 02.09).
                // Именно он живёт на приборке, и именно его человек сверяет.
                value: GarageFormat.odometer(vehicle.displayOdometerKm, lng: l),
                valueColor: c.text,
                unit: AppStrings.km(l),
                label: vehicle.manualOdometerKm == nil
                    ? AppStrings.odometerLabel(l)
                    : AppStrings.odometerRealLabel(l),
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

    // MARK: - Паспорт машины (0.6.4)

    /// Три числа над всем остальным — приём, взятый у drive2 и повёрнутый на
    /// наш предмет: у них в кругах «драйв / читают / записи», у нас география.
    /// «Читают» в круг не ставим — это тщеславие, а не биография.
    private func passportCircles(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        // Показываются ВСЕГДА, даже когда все три нуля. Первая версия пряталась
        // при отсутствии поездок — и у машины, к которой ничего не привязано (а
        // привязка необязательная), экран выглядел точно как до паспорта.
        // Пустая биография — это состояние блока, а не повод его убрать.
        // Пока считаем — прочерки, а не нули. У машины с тремя сотнями поездок
        // экран на каждом открытии показывал «0 поездок · 0 регионов · 0 дней»
        // и подпись «Биография пока пустая», то есть состояние загрузки было
        // пиксель в пиксель равно состоянию «ничего нет» — и врало.
        let p = passport ?? Passport()
        let ready = passport != nil
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                circle(ready ? String(p.tripCount) : "—", AppStrings.nounTrips(l, p.tripCount), c: c)
                circle(ready ? String(p.regionCount) : "—", AppStrings.nounRegions(l, p.regionCount), c: c)
                circle(ready ? String(p.daysOnRoad) : "—", AppStrings.nounDays(l, p.daysOnRoad), c: c)
            }
            if ready, p.tripCount == 0 {
                Text(AppStrings.vehicleBiographyEmpty(l))
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// «Volkswagen Polo · 2019 · седан» — из полей паспорта, пустые пропускаются.
    /// `nil`, когда не заполнено ничего: подпись из одной точки хуже её отсутствия.
    private func modelLine(_ v: Vehicle, _ l: LanguageManager.Language) -> String? {
        var parts: [String] = []
        let makeModel = [v.make, v.model].filter { !$0.isEmpty }.joined(separator: " ")
        if !makeModel.isEmpty { parts.append(makeModel) }
        if v.year > 0 { parts.append(String(v.year)) }
        if !v.bodyType.isEmpty {
            parts.append(AppStrings.avatarStyleName(l, style: v.bodyType).lowercased(l))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func circle(_ value: String, _ label: String, c: AppTheme.Colors) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(c.text)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// Строка владельца о машине — единственное, что взято у бортжурнала, и
    /// взято одним предложением: «почему именно она» GPS не произведёт никогда.
    /// Пусто — карточки нет: пустая рамка с приглашением писать противоречит
    /// тому, что паспорт заполняется сам.
    @ViewBuilder
    private func aboutCard(_ vehicle: Vehicle, c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if !vehicle.about.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(vehicle.about)
                    .font(.system(size: 13))
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    Text(AppStrings.vehicleAboutFooter(l))
                        .font(.system(size: 11))
                        .foregroundStyle(c.textTertiary)
                    Spacer(minLength: 8)
                    Button {
                        Haptics.tap()
                        showEditForm = true
                    } label: {
                        Text(AppStrings.edit(l))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    /// «Где была» — карта именно этой машины. Не новый рендер: тот же
    /// `LightRoutePreview`, которым нарисована карточка-вход «Карта» в чужом
    /// профиле. Форк дал бы два места, где маршрут рисуется по-разному.
    @ViewBuilder
    private func whereWasCard(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let p = passport, !p.routes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.vehicleWhereWas(l))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(c.text)
                        Text(placesLine(p, l))
                            .font(.system(size: 12))
                            .foregroundStyle(c.textTertiary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { Haptics.tap(); showMap = true }
                // Жест сам по себе не элемент управления: VoiceOver его не
                // назовёт, а Switch Control до него не доберётся вовсе.
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                // Настоящая карта, а не набросок: `LightRoutePreview` без
                // подложки читался как две закорючки в пустоте. Здесь
                // MapKit-снимок с маршрутами машины.
                VehicleMiniMap(routes: p.routes)
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    /// «8 регионов · 22 города». Отдельной функцией, а не интерполяцией в
    /// `body`: четыре подстановки в одной строке — это минуты тайпчекинга и
    /// сборка, которая не укладывается в лимит.
    private func placesLine(_ p: Passport, _ l: LanguageManager.Language) -> String {
        let regions = "\(p.regionCount) " + AppStrings.nounRegions(l, p.regionCount)
        let cities = "\(p.cityCount) " + AppStrings.nounCities(l, p.cityCount)
        return regions + " · " + cities
    }

    /// «Поездки этой машины» — приём из бортжурнала drive2, переведённый на
    /// нашу валюту: у них справа деньги и пробег, у нас километры.
    @ViewBuilder
    private func vehicleTrips(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let p = passport, !p.recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(AppStrings.vehicleTripsTitle(l))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(c.text)
                    Spacer()
                    Text(String(p.tripCount))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { Haptics.tap(); showTrips = true }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                ForEach(0..<p.recent.count, id: \.self) { idx in
                    let trip = p.recent[idx]
                    if idx > 0 { Divider().overlay(c.border) }
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                // Замок и здесь: человек, проверяющий, что из
                                // его гаража видно другим, смотрит именно на
                                // ЭТУ карточку, а полный список — на тап глубже.
                                // Без замка ответ на его вопрос был неверным.
                                if trip.isPrivate {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(c.textTertiary)
                                }
                                Text(TripRowText.title(trip, l))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(c.text)
                                    .lineLimit(1)
                            }
                            Text(TripRowText.when(trip, l))
                                .font(.system(size: 11))
                                .foregroundStyle(c.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Text(TripRowText.km(trip, l))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(c.text)
                    }
                    .frame(minHeight: 38)
                    .contentShape(Rectangle())
                    .onTapGesture { Haptics.tap(); openTripId = trip.id }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(14)
            .surfaceCard(cornerRadius: 16)
        }
    }

    /// Рекорды ИМЕННО ЭТОЙ машины. Ни строчки нового расчёта: тот же
    /// `MeAggregates.compute`, которому всё равно, чьи поездки ему дали.
    ///
    /// Одна карточка со строками, а не три отдельных: три штуки по сорок
    /// точек высоты растягивали низ экрана на пустоту, а цветные кружки
    /// рядом с ними ничего не кодировали — зелёный и красный не значили
    /// «хорошо» и «плохо», это был просто разный цвет у соседних строк.
    @ViewBuilder
    private func vehicleRecords(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        if let agg = passport?.agg, agg.tripCount > 0 {
            VStack(alignment: .leading, spacing: 10) {
                GarageSectionLabel(text: AppStrings.statsRecords(l), color: c.textSecondary)

                VStack(spacing: 0) {
                    recordRow(AppStrings.recordLongest(l),
                              agg.longestTripTitle ?? agg.longestTripRegion ?? "—",
                              kmValue(agg.longestTripKm, l), c: c,
                              opens: agg.longestTripId)

                    if let peak = passport?.highest, peak.meters > 0 {
                        rowDivider(c)
                        recordRow(AppStrings.recordHighest(l), peak.title,
                                  metersValue(peak.meters, l), c: c)
                    }

                    if agg.maxDayKm > 0 {
                        rowDivider(c)
                        recordRow(AppStrings.statsRecordBestDay(l),
                                  agg.longestTripDate.map { Self.dayFormatter(l).string(from: $0) } ?? "—",
                                  kmValue(agg.maxDayKm, l), c: c)
                    }

                    // `maxDayDuration` считался с самого начала, а показать его
                    // было негде — как и строку `recordLongestDay`, которая
                    // лежала переведённой на тринадцать языков без единого
                    // вызова. Километры и часы — разные рекорды: день из шести
                    // часов в пробке не тот же, что день из шестисот километров.
                    if agg.maxDayDuration > 0 {
                        rowDivider(c)
                        recordRow(AppStrings.recordLongestDay(l),
                                  AppStrings.recordLongestDaySubtitle(l),
                                  Trip.formattedTimeHuman(agg.maxDayDuration, lang: l), c: c)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 2)
                .surfaceCard(cornerRadius: 16)
            }
        }
    }

    /// Разделитель между строками внутри одной карточки.
    private func rowDivider(_ c: AppTheme.Colors) -> some View {
        Divider().overlay(c.border)
    }

    private func kmValue(_ km: Double, _ l: LanguageManager.Language) -> String {
        GarageFormat.odometer(km, lng: l) + " " + AppStrings.km(l)
    }

    private func metersValue(_ m: Double, _ l: LanguageManager.Language) -> String {
        GarageFormat.odometer(m, lng: l) + " " + AppStrings.unitMeters(l)
    }

    /// `opens` — поездка, о которой рекорд. Строка «самая длинная» без
    /// возможности её открыть заставляет искать ту же поездку руками в списке.
    @ViewBuilder
    private func recordRow(_ label: String, _ subtitle: String, _ value: String,
                           c: AppTheme.Colors, opens tripId: UUID? = nil) -> some View {
        let row = HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(c.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(c.text)
            }
        }
        .frame(minHeight: 46)

        if let tripId {
            Button {
                Haptics.tap()
                openTripId = tripId
            } label: {
                row.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private static func dayFormatter(_ l: LanguageManager.Language) -> DateFormatter {
        let f = DateFormatter()
        f.locale = l.locale
        f.setLocalizedDateFormatFromTemplate("dMMMMyyyy")
        return f
    }

    /// Считает биографию машины вне главного актора: разбор полилиний на
    /// сотнях поездок — это секунды заморозки, если делать его в `body`.
    private func loadPassport() async {
        let id = vehicleId
        let built = await Task.detached(priority: .userInitiated) { () -> Passport in
            // Репозиторий напрямую: `TripManager` заводится с `LocationManager`
            // и синглтона не имеет, а здесь нужно только прочитать поездки.
            let repo: TripRepository = CoreDataTripRepository()
            let mine = repo.fetchTripsForMap()
                .filter { $0.vehicleId == id && !$0.isTransfer }
            guard !mine.isEmpty else { return Passport() }
            let agg = MeAggregates.compute(trips: mine, now: Date(), calendar: .current)
            let cal = Calendar.current
            let days = Set(mine.map { cal.startOfDay(for: $0.startDate) }).count
            // Та же функция, что строит карту профиля, только с поездками одной
            // машины — ровно как обещал `VehicleMapFeasibilityTests`.
            await RegionAtlas.shared.loadIfNeeded()
            let exploration = MapExploration.build(
                trips: mine,
                visitedHashes: TerritoryManager.geohashes(
                    fromTrips: mine.map { $0.previewCoordinates }, precision: 6),
                atlas: RegionAtlas.shared
            )
            let routes = mine.prefix(120).map { $0.previewCoordinates }.filter { $0.count >= 2 }
            return Passport(tripCount: mine.count,
                            regionCount: exploration.regions.count,
                            daysOnRoad: days,
                            agg: agg,
                            recent: Array(mine.prefix(3)),
                            routes: Array(routes),
                            cityCount: exploration.regions.reduce(0) { $0 + $1.visitedCityCount },
                            highest: mine.max(by: { $0.elevation < $1.elevation }).map {
                                ($0.title ?? $0.region ?? "—", $0.elevation)
                            })
        }.value
        passport = built
        mainPhoto = VehiclePhotoStore.mainPhoto(of: id)
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

    /// Магнитола и автозапись — про одно и то же, поэтому живут одной
    /// группой под общим заголовком. Раздельными карточками они читались
    /// как два несвязанных сообщения, между которыми ещё и дырка.
    private func recordingSection(c: AppTheme.Colors, l: LanguageManager.Language) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GarageSectionLabel(text: AppStrings.vehicleRecordingSection(l), color: c.textSecondary)
            VStack(spacing: 0) {
                stereoStatusCard(c: c, l: l)
                rowDivider(c).padding(.leading, 14)
                autoRecordRow(c: c, l: l)
            }
            .surfaceCard(cornerRadius: 16)
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
            settings.selectVehicle(id: settings.recordableVehicles.first?.id)
        }
        dismiss()
    }
}
