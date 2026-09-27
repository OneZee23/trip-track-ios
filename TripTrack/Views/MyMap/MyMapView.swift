import SwiftUI
import MapKit
import UIKit

/// Atlas 0.8.1: live roads under the paper map, with appearance
/// controls and a permanent sheet for exploring regions, cities and trips.
struct MyMapView: View {
    @EnvironmentObject private var mapVM: MapViewModel
    @EnvironmentObject private var lang: LanguageManager
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.colorScheme) private var scheme
    // Singleton by design — survives tab switches (see MyMapViewModel.shared).
    @ObservedObject private var vm = MyMapViewModel.shared
    @State private var zoomLevel: MapZoomLevel = .far
    /// Wrapper rather than a retroactive `UUID: Identifiable` conformance —
    /// that one would leak app-wide from a map file.
    private struct OpenedTrip: Identifiable { let id: UUID }
    @State private var openedTrip: OpenedTrip?
    /// Lives here, not in the sheet, so the tab bar can hide under the
    /// pulled-up region list too.
    @State private var isSummaryExpanded = false
    /// Постер собирается (снимок карты качается из сети). Живёт здесь, потому
    /// что здесь же и заказ — см. `posterProgress`.
    @State private var isRenderingPoster = false
    /// Карточка нерешённой загадки, открытая тапом по кругу или по значку.
    /// Модель целиком, а не id: пока она здесь, карточка показана, а кольцо
    /// этой подсказки горит ярче (`selectedHintId`). Закрытие листа обнуляет
    /// её само — второго места, где снимается выбор, нет.
    @State private var openedHint: RiddleHintCardModel?
    /// Карточка «Атлас в бете», открытая тапом по `AtlasBetaChip`.
    @State private var showBetaSheet = false
    /// Единственное, о чём «Атлас» говорит всплывающей строкой, — несобравшийся
    /// постер: остальное он показывает самой картой.
    @State private var toast: ToastItem?
    @State private var showAppearance = false
    @State private var showExplanation = false
    /// Положение шторки. Геометрию и правила жеста держит `AtlasSlot` —
    /// чистый и под тестами (`AtlasSlotTests`).
    @State private var detent: AtlasSheetDetent = .collapsed
    /// Живой верх шторки во время жеста: за ним в реальном времени идут
    /// кнопки карты и подпись Apple — «одна пружина на всё нижнее».
    @State private var liveTop: CGFloat?

    /// «Есть туман или нет» is not a question a screenshot can settle by eye —
    /// a night map is dark either way. `-no-fog-veil` draws the same map
    /// without it so a test can measure the difference in luminance.
    #if DEBUG
    static let showsVeil = !ProcessInfo.processInfo.arguments.contains("-no-fog-veil")
    #else
    static let showsVeil = true
    #endif

    /// Тело разрезано на `body` и `stage` по той же причине, что у
    /// `TripDetailView` и `ProfileView`: цепочка модификаторов на «Атласе»
    /// уже длинная, а вывод типов SwiftUI падает по таймауту в случайном
    /// месте, а не там, где добавили строку.
    var body: some View {
        stage(slot)
    }

    /// Геометрия слота — из `WindowLayoutMetrics`, снимка окна ПОСЛЕ разметки
    /// UIKit.
    ///
    /// Не из `GeometryReader`: внутри безопасной зоны он отдаёт её отступы
    /// НУЛЯМИ (они уже съедены родителем), и слот вставал на сто точек выше —
    /// поймано первым же кадром на симуляторе. И не из живого `UIWindow`:
    /// запрос окна прямо в `body` уже однажды зациклил разметку «Атласа»
    /// (CLAUDE.md, 0.8.1).
    private var slot: AtlasSlot {
        let metrics = WindowLayoutMetrics.shared
        let size = metrics.size ?? CGSize(width: 390, height: 844)
        let insets = metrics.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        return AtlasSlot(height: size.height, safeTop: insets.top, safeBottom: insets.bottom)
    }

    private func stage(_ slot: AtlasSlot) -> some View {
        ZStack {
            MyMapRepresentable(
                exploration: vm.exploration,
                revealed: vm.revealed,
                veil: Self.showsVeil ? vm.fogVeil : nil,
                vein: vm.routeVein,
                selectedRoute: vm.selectedRoute,
                selection: vm.selection,
                seals: vm.seals,
                riddleHints: vm.riddleHints,
                selectedHintId: openedHint?.id,
                placePins: vm.placePins,
                selectedPlaceId: vm.selectedPlaceId,
                language: lang.language,
                // Логотип Apple и «Legal» встают над свёрнутым листом: под
                // непрозрачным туманом он накрыл бы их насовсем.
                // Подпись Apple стоит на 8 pt выше ВЕРХА СЛОТА (спека §2).
                //
                // Два ограничения, и оба дорогие. Первое: значение берётся по
                // ПОЛОЖЕНИЮ, а не по живому верху во время жеста — инсеты
                // карты это проход разметки MapKit, и шестьдесят таких
                // проходов в секунду стоят дороже, чем идеальное следование
                // подписи за пальцем. Второе: по СПИСКУ оно не считается
                // никогда. В списке верх шторки на 104, и инсет вышел бы 748
                // на карте высотой 844 — а MapKit кадрирует камеру по СУММЕ
                // полей разметки и `edgePadding` (CLAUDE.md, 0.8.1: «оставалось
                // минус 68 pt, и MapKit отвечал кадром в 5.34 раза шире
                // запрошенного»). Подписи в списке по спеке нет всё равно.
                bottomOverlayHeight: slot.attributionInset(detent),
                // И по ЛЕВОМУ краю той же карточки: две левые границы в одном
                // углу экрана ничего друг про друга не объясняют.
                bottomOverlayMaxWidth: MyMapSheet.summaryMaxWidth,
                appearance: vm.appearance,
                model: vm,
                onZoomLevelChange: { zoomLevel = $0 },
                onSelectTrip: { vm.select(.trip($0)) },
                onSelectRoad: { vm.selectRoad($0) },
                // Камера не двигается: палец уже стоит на печати.
                onSelectDiscovery: { vm.select(.discovery($0), zoom: false) },
                // Камера не двигается и здесь: круг уже на экране, а его
                // середина — не ответ (`RiddleHint.offsetCentre`).
                onSelectHint: { openHint($0) },
                onSelectPlace: { vm.selectedPlaceId = $0 },
                // Auto-zoom to the region only from the country view, where
                // that IS the gesture. Down at street level a tap that misses
                // the road is a miss, and answering it by flinging the camera
                // out to the whole krai loses your place.
                onTapMap: {
                    // Промах по карте снимает карточку места — как и любой
                    // другой выбор: двух открытых карточек на экране нет.
                    vm.selectedPlaceId = nil
                    vm.selectRegion(at: $0, zoom: zoomLevel == .far)
                },
                cameraCommand: $vm.cameraCommand
            )
            .ignoresSafeArea()

            topScrim

            title
                .opacity(headerOpacity(slot))
                .allowsHitTesting(headerOpacity(slot) > 0.5)

            mapControls(slot)

            if vm.isEmpty {
                emptyState
            }

            if vm.isLoading || vm.isFiltering {
                CarLoadingView()
            }

            // Выбранный объект (регион, дорога, поездка, находка) держит
            // ПРЕЖНЮЮ панель: своих состояний у них в спеке v3 нет вовсе, а
            // карта их открывать умеет и сегодня. Новая шторка живёт там, где
            // спека её описывает, — на сводке и списке.
            if vm.selection == nil {
                atlasSheet(slot)
            } else {
                MyMapSheet(
                    vm: vm,
                    isSummaryExpanded: $isSummaryExpanded,
                    onOpenTrip: { openedTrip = OpenedTrip(id: $0) },
                    // Камера ДВИГАЕТСЯ — в отличие от тапа по печати на карте:
                    // из списка человек не знает, в какой угол мира смотрит
                    // карта, и карточка над пустым местом не отвечает «где это
                    // было».
                    onOpenDiscovery: { vm.focusDiscovery($0) },
                    onShare: shareSummary,
                    onSettings: { showAppearance = true },
                    onExplain: { showExplanation = true }
                )
            }

            placeCard(slot)

            posterProgress
        }
        .animation(.easeOut(duration: 0.2), value: isRenderingPoster)
        .toast(item: $toast)
        // Canon frames 2–5 have no tab bar: a selected card owns the bottom
        // of the screen, and the bar sitting on top of it clipped the
        // progress row clean off.
        // Бар уезжает ТОЛЬКО под журнал: тот забирает почти весь экран, и
        // пилюля поверх него закрывала бы список.
        //
        // Под карточкой (край, дорога, поездка, находка) бар ОСТАЁТСЯ. Канон
        // 0.7.0 прятал и его — «a selected card owns the bottom of the
        // screen», — но на устройстве он всё равно оставался, и владелец
        // дважды прислал кадр, где пилюля лежит на карточке: «сливается всё,
        // некрасиво». Два состояния, из которых одно не воспроизводится, —
        // это не правило, а лотерея; поэтому карточка теперь ВСЕГДА кладётся
        // выше бара (`MyMapSheet.detailPanel`), и выглядит одинаково везде.
        .hideAppTabBar(isSummaryExpanded)
        // Выбранное место забирает слот себе, и сводка сжимается до одной
        // строки: «карточка места и строка подсказки никогда не показываются
        // одновременно со сводкой» (чек-лист спеки). Снятие выбора возвращает
        // сводку — но не трогает список, если человек его сам раскрыл.
        .onChange(of: vm.selectedPlaceId) { _, id in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                if id != nil {
                    detent = .peek
                } else if detent == .peek {
                    detent = .collapsed
                }
            }
        }
        .onAppear {
            // Diagnostic (round 2, 19 сен 2026): fires once this subtree has
            // been laid out — the closest SwiftUI gets to "first frame of
            // this screen drew". Refires on every visit to the Maps tab
            // (`ContentView` destroys/rebuilds `MyMapView` on tab switch —
            // see `AppTab` doc), so cold (first ever) vs warm (revisit,
            // `MyMapViewModel.shared`/`BundleRiddleCatalog.shared` already
            // built) both show up in the trace naturally.
            StartupTrace.mark("MyMapView.onAppear")
        }
        .task {
            await vm.loadIfNeeded(tripManager: mapVM.tripManager, territory: mapVM.territoryManager)
        }
        // Вторая фаза перехода с экрана итогов: вкладка уже переключена, стек
        // карты смонтирован — можно везти камеру к печати (`focusDiscovery`
        // сам дождётся выборки, если печати ещё нет в списке).
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDiscovery)) { note in
            guard let id = note.object as? UUID else { return }
            vm.focusDiscovery(id)
        }
        .sheet(item: $openedHint) { model in
            RiddleHintCard(model: model)
                .padding(.bottom, 20)
                .contentSizedSheet(background: AppTheme.colors(for: scheme).bg)
        }
        .sheet(isPresented: $showBetaSheet) {
            AtlasBetaSheet(model: .make(), onDismiss: { showBetaSheet = false })
                .contentSizedSheet(background: AppTheme.colors(for: scheme).bg)
        }
        .sheet(isPresented: $showAppearance) {
            // Высота ЧИСЛОМ, а не измерением.
            //
            // `.medium` оставлял под тумблером пустое поле в треть телефона
            // (владелец 26 сен), а `contentSizedSheet` на этом листе
            // схлопывал его до одной шапки: у листа внутри растягивающиеся
            // дети, измерение уходит вниз и не возвращается. Две попытки
            // мерить кончились сломанным экраном у владельца, поэтому здесь
            // стоит константа: три плитки (150) + тумблер (56) + шапка (64) +
            // поля. Меняешь содержимое листа — меняй и её; это честная цена
            // за то, что лист не может схлопнуться ни при каком порядке
            // проходов разметки.
            AtlasAppearanceSheet(appearance: Binding(
                get: { vm.appearance },
                set: { vm.setAppearance($0) }
            ))
                .presentationDetents([.height(340)])
        }
        .sheet(isPresented: $showExplanation) {
            AtlasExplanationSheet()
                .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $openedTrip) { opened in
            NavigationStack {
                TripDetailView(
                    tripId: opened.id,
                    viewModel: TripsViewModel(tripManager: mapVM.tripManager)
                )
            }
        }
    }

    // MARK: - Слот

    /// Верх шторки прямо сейчас: во время жеста — живой, иначе по положению.
    private func sheetTop(_ slot: AtlasSlot) -> CGFloat {
        liveTop ?? slot.top(of: detent)
    }

    /// Прозрачность заголовка вкладки.
    ///
    /// У ВЫБРАННОГО объекта заголовок не гаснет никогда: в нём живёт кнопка
    /// «назад», и погасив её вместе с заголовком, экран региона остался бы
    /// без выхода — из списка регион как раз и открывают, то есть при
    /// раскрытой шторке, где рампа даёт ноль.
    private func headerOpacity(_ slot: AtlasSlot) -> CGFloat {
        guard vm.selection == nil else { return 1 }
        return AtlasSlot.headerOpacity(sheetTop: sheetTop(slot))
    }

    /// Верх СЛОТА: то, за чем следуют кнопки карты и подпись Apple.
    ///
    /// Пока выбрано место, слот занимает карточка, и следовать надо за ней, а
    /// не за сжавшейся шторкой (принцип 1 — слот один на двоих).
    private func slotTop(_ slot: AtlasSlot) -> CGFloat {
        guard vm.selectedPlace != nil else { return sheetTop(slot) }
        return placeCardAnchor(slot) - 12 - AtlasPlaceCard.height
    }

    private func atlasSheet(_ slot: AtlasSlot) -> some View {
        AtlasSheet(
            slot: slot,
            variant: .summary,
            detent: $detent,
            liveTop: $liveTop,
            onTapCollapsed: { toggleSheet() },
            accessibilityTitle: AppStrings.atlasExplored(lang.language)
        ) {
            AtlasSummaryContent(
                vm: vm,
                detent: detent,
                onShare: shareSummary,
                onExplain: { showExplanation = true },
                onOpenRegion: { vm.select(.region($0)) },
                // БЕЗ `isSummaryExpanded`: он прячет таб-бар, а спека это
                // запрещает прямо — «таб-бар стоит всегда и никогда не
                // анимируется сам по себе». Его накрывают только модальные
                // шторки.
                onOpenTrips: { detent = .expanded },
                onOpenCities: { detent = .expanded },
                onSearch: { detent = .expanded },
                onTapPeek: { detent = .expanded }
            )
        }
        .frame(maxHeight: .infinity, alignment: .top)
        // Верх шторки задан в координатах ЭКРАНА, значит и слой обязан
        // начинаться от края экрана, а не от безопасной зоны.
        .ignoresSafeArea()
    }

    /// Тап по свёрнутой шторке раскрывает список, по раскрытой — сворачивает.
    private func toggleSheet() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            detent = detent == .expanded ? .collapsed : .expanded
        }
    }

    // MARK: - Chrome

    /// Paper fading over the map keeps the title and status bar readable.
    private var topScrim: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [AtlasTheme.background.opacity(0.8), AtlasTheme.background.opacity(0)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 110)
            .ignoresSafeArea(edges: .top)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    /// The selected region takes over the map header, as in HTML A3.
    private var title: some View {
        VStack(spacing: 0) {
            if let region = vm.selectedRegion {
                regionTitle(region)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(AppStrings.myMapTitle(lang.language))
                            .font(AppType.title)
                            .tracking(AppType.titleTracking)
                            .foregroundStyle(AtlasTheme.ink)
                            .allowsHitTesting(false)

                        AtlasBetaChip { showBetaSheet = true }
                        Spacer(minLength: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            Spacer()
        }
    }

    private func regionTitle(_ region: MapRegionStat) -> some View {
        HStack(spacing: 10) {
            control("chevron.left", label: AppStrings.back(lang.language), id: "mymap_close") {
                vm.select(nil)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(regionSubtitle(region))
                    .font(AppType.caption)
                    .foregroundStyle(AtlasTheme.secondary)
                Text(region.localizedName(lang.language))
                    .font(AppType.headerTitle)
                    .foregroundStyle(AtlasTheme.ink)
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        .background(AtlasTheme.background.opacity(0.92))
    }

    private func regionSubtitle(_ region: MapRegionStat) -> String {
        let country = RegionAtlas.shared.countryName(region.countryCode, lang.language) ?? region.countryCode
        guard let date = region.firstVisited else { return country }
        return country + " · " + AppStrings.mapRegionSince(lang.language, date: date)
    }

    /// Капсула кнопок карты, привязанная к верху слота (спека §3.4, S1).
    ///
    /// Отступ 12 pt над слотом и затухание между 300 и 240 — числа спеки,
    /// считает их `AtlasSlot`.
    private func mapControls(_ slot: AtlasSlot) -> some View {
        let top = slotTop(slot)
        return VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                AtlasMapControls(
                    // В пустом атласе выбирать нечего: остаётся одно «Моё
                    // местоположение», и капсула становится кругом сама.
                    showsLayers: !vm.isEmpty,
                    locationDenied: mapVM.locationDenied,
                    layersLabel: AppStrings.atlasMapStyle(lang.language),
                    locationLabel: AppStrings.atlasMyLocation(lang.language),
                    onLayers: { showAppearance = true },
                    onLocate: {
                        // Спрашивается РАЗРЕШЕНИЕ, а не живой фикс: наш
                        // `LocationManager` на «Атласе» не запущен вовсе, и
                        // гейт по нему врал всегда (владелец 27 сентября).
                        guard !mapVM.locationDenied else {
                            vm.fitAll()
                            toast = ToastItem(type: .info,
                                              message: AppStrings.atlasLocationUnavailable(lang.language))
                            return
                        }
                        vm.locateUser()
                    }
                )
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, Swift.max(0, slot.height - top + AtlasSlot.controlsGap))
        .opacity(AtlasSlot.controlsOpacity(slotTop: top))
        .allowsHitTesting(AtlasSlot.controlsOpacity(slotTop: top) > 0.5)
        .ignoresSafeArea(edges: .bottom)
    }

    private func control(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(AtlasTheme.ink).frame(width: 44, height: 44)
                .background(AtlasTheme.control, in: Circle())
                .shadow(color: .black.opacity(0.12), radius: 7, y: 2)
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// «1 910 км открыто · 4 региона» — километры берутся из слоя открытого,
    /// а не из суммы поездок: сотый проезд по своей улице не открывает
    /// ничего, и подпись под «Атласом» обязана считать то же, что видно
    /// глазами на карте.
    private var openedSummary: String {
        var parts = [
            AppStrings.mapOpenedSummary(
                lang.language,
                distance: Measure.distance(
                    km: vm.revealed.openedKm, unit: distanceUnit, lang: lang.language),
                regions: vm.exploration.regionCount
            )
        ]
        // Ноль не печатается вовсе. «0 знаков» под «Атласом» — это обещание
        // механики тому, у кого её ещё нет: печать появится сама, и объявлять
        // её отсутствие незачем.
        if !vm.seals.isEmpty {
            parts.append(AppStrings.mapSealsCount(lang.language, count: vm.seals.count))
        }
        if !vm.riddleHints.isEmpty {
            parts.append(AppStrings.mapRiddlesNear(lang.language, count: vm.riddleHints.count))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            if vm.period == .allTime {
                EmptyStateIllustration(name: "empty_map", size: 120)
            } else {
                Image(systemName: "calendar.badge.minus")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(AtlasTheme.secondary)
            }
            Text(AppStrings.emptyMapTitle(lang.language))
                .font(.inter(18, weight: .semibold))
                .foregroundStyle(AtlasTheme.ink)
            Text(AppStrings.emptyMapSubtitle(lang.language))
                .font(.inter(13))
                .foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 280)
        .padding(.bottom, MyMapSheet.collapsedHeight * 0.5)
    }

    // MARK: - Загадка

    /// Тап по кругу или по значку подсказки: собрать карточку и показать её.
    ///
    /// Строка и расстояние берутся ИЗ ЖУРНАЛА (`Journal.NearbyRiddle`), а не
    /// считаются заново: расстояние до края круга уже посчитано там, от
    /// центроидов открытого, и второй счёт однажды разошёлся бы с первым — как
    /// расходились километры до `TripDistanceGate`. Круга нет в журнале
    /// (пересчёт плана уже прошёл, а тап приехал от прежней аннотации) —
    /// карточки не будет: показывать пустую нечем.
    /// Карточка нажатой булавки места (макет S8).
    ///
    /// Стоит НАД свёрнутым листом, а не у самой булавки: перевести координату
    /// карты в точку экрана из SwiftUI нечем, а карточка у края экрана уехала
    /// бы за него. Ведёт она на экран места — во вкладку «Места», тем же
    /// двухфазным переходом (`.openPlace`), что и чип отметки в поездке.
    /// Карточка выбранного места в слоте (спека §3.7).
    ///
    /// Стоит на 12 pt выше строки подсказки, а на экранах ниже 700 pt —
    /// на 12 pt над таб-баром: строки подсказки там нет вовсе (спека §9).
    @ViewBuilder
    private func placeCard(_ slot: AtlasSlot) -> some View {
        if let place = vm.selectedPlace {
            VStack {
                Spacer(minLength: 0)
                AtlasPlaceCard(
                    name: place.name ?? AppStrings.placeUnnamed(lang.language),
                    line: placeCardLine(place),
                    actionTitle: AppStrings.atlasOpenPlace(lang.language),
                    onOpen: {
                        Haptics.tap()
                        NotificationCenter.default.post(name: .openPlace, object: place.id)
                    },
                    onClose: { vm.selectedPlaceId = nil }
                )
                .padding(.horizontal, AtlasTheme.sideInset)
                .padding(.bottom, Swift.max(0, slot.height - placeCardAnchor(slot) + 12))
            }
            .ignoresSafeArea()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// Что стоит под карточкой: строка подсказки или сразу таб-бар.
    private func placeCardAnchor(_ slot: AtlasSlot) -> CGFloat {
        slot.showsPeekRow ? slot.peekTop : slot.tabBarTop
    }

    private static let placeDayMonth = LocalizedDateFormatter.templates("dMMM")

    /// «Здесь 12 раз · 20 сент.»: сколько раз и когда последний.
    ///
    /// Времени в пути здесь больше нет, и это спека, а не потеря: «адрес,
    /// расстояние, время в пути живут на своих экранах» (§3.7). Карточка
    /// отвечает на «что это и сколько раз», а не пересказывает экран места.
    private func placeCardLine(_ place: AtlasPlacePin) -> String {
        let l = lang.language
        let here = AppStrings.placeHereTimes(l, count: place.passCount)
        guard let last = place.lastAt, let f = Self.placeDayMonth[l] else { return here }
        return here + " · " + AppStrings.placeLastPass(l, date: f.string(from: last))
    }

    private func openHint(_ id: String) {
        guard let riddle = vm.journal.riddles.first(where: { $0.id == id }) else { return }
        openedHint = RiddleHintCardModel.make(
            riddle: riddle, unit: distanceUnit, lang: lang.language)
    }

    // MARK: - Share

    /// Кнопка на свёрнутом листе отдаёт КАРТИНКУ — снимок карты с тем же
    /// туманом и теми же печатями, что на экране (`AtlasSharePoster`), — и
    /// ту же строку итога следом.
    ///
    /// До 0.7.0 уезжал один текст, и это был честный ответ, пока карты под
    /// ним не было: показывать было нечего. Туман показывать есть что, а
    /// текст остаётся рядом с картинкой — им делятся туда, где картинка не
    /// разворачивается.
    ///
    /// Снимок не пришёл (нет сети — плитки карты качаются из неё) — уходит
    /// один текст, как раньше. Отказывать в шеринге из-за картинки нельзя.
    private func shareSummary() {
        guard !isRenderingPoster, !vm.isFiltering else { return }
        isRenderingPoster = true
        let text = openedSummary
        let title = AppStrings.myMapTitle(lang.language)
        let caption = AppStrings.posterCaption(
            lang.language,
            distance: Measure.distance(
                km: vm.revealed.openedKm, unit: distanceUnit, lang: lang.language),
            seals: vm.seals.count
        )
        Task {
            let poster = await AtlasSharePoster.make(vm: vm, caption: caption)
            isRenderingPoster = false
            // Картинки нет — говорим об этом. Лист всё равно откроется, в нём
            // останется одна строка про открытые километры, и молчание здесь
            // читается как «кнопка только это и умеет».
            if poster == nil {
                toast = ToastItem(type: .error, message: AppStrings.posterFailed(lang.language))
            }
            await AtlasSharePoster.present(image: poster, text: text, title: title)
        }
    }

    /// «Готовим снимок…» поверх карты, пока собирается постер.
    ///
    /// Пилюля, а не спиннер В САМОЙ кнопке: кнопка живёт в `MyMapSheet`, и
    /// заводить ради двух секунд ожидания ещё одно состояние в чужом файле —
    /// это вторая правда о том, идёт ли сборка. Пилюля стоит над свёрнутым
    /// листом, то есть там же, куда смотрит палец, и не закрывает ни лист,
    /// ни таб-бар. Модалки нет нарочно: ждать нечего — нажатие уже отвечено.
    @ViewBuilder
    private var posterProgress: some View {
        if isRenderingPoster {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text(AppStrings.shareRendering(lang.language))
                        .font(.inter(13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.bottom, MyMapSheet.collapsedHeight + 8)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityIdentifier("mymap_share_progress")
        }
    }
}

/// Figma empty-state zigzag: M1.5 21.5 L16.5 4.5 L33.5 15.5 L49.5 1.5 in a
/// 51×23 box, scaled to the frame.
struct ZigzagTrailIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 51.0, sy = rect.height / 23.0
        var p = Path()
        p.move(to: CGPoint(x: 1.5 * sx, y: 21.5 * sy))
        p.addLine(to: CGPoint(x: 16.5 * sx, y: 4.5 * sy))
        p.addLine(to: CGPoint(x: 33.5 * sx, y: 15.5 * sy))
        p.addLine(to: CGPoint(x: 49.5 * sx, y: 1.5 * sy))
        return p
    }
}
