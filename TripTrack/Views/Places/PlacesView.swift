import SwiftUI

/// Вкладка «Места» — по макету «TripTrack · Места» (0.8.1).
///
/// Палитра, отступы и нижняя панель те же, что у «Атласа»: бумажный фон,
/// белые карточки радиусом 18, набор `AppType`. Терракота достаётся
/// действию и одному крупному числу на экране места — в списке её нет
/// вовсе, поэтому чип «частый гость» серый, а «обычно…» не акцентная.
///
/// Экран растёт вместе с библиотекой, и ступеней ровно три:
/// - пусто (S2) — что это вообще такое, с примером, помеченным «Пример»;
/// - новичок (S3) — мест ещё нет, но подсказка уже есть, и рядом поездки,
///   в которых можно поставить отметку руками;
/// - список (S1) — карта, «Мои места», подсказки; а от
///   `PlacesPresentation.manyPlaces` к ним добавляются поиск, порядок и
///   группы (S6). Раньше порога их нет нарочно: искать среди четырёх
///   строк нечего, а три лишних контрола над списком из трёх мест — это
///   и есть «экран пустой какой-то», только с другой стороны.
struct PlacesView: View {
    @EnvironmentObject private var lang: LanguageManager
    @EnvironmentObject private var mapVM: MapViewModel
    @Environment(\.distanceUnit) private var distanceUnit
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = PlacesTabViewModel()
    @State private var path: [PlacesDest] = []
    @State private var query = ""
    @State private var sort = PlacesSort.load()
    /// Положение панели. Источник правды один — выбор булавки и пустая
    /// вкладка тоже пишут сюда, а не заводят своё состояние: панель на
    /// вкладке ОДНА (принцип 1 спеки).
    @State private var stop: PlacesPanelStop = .half
    /// Живой верх во время жеста: за ним идут поля карты.
    @State private var liveTop: CGFloat?
    /// Куда вернуться, сняв выбор булавки.
    @State private var stopBeforeSelection: PlacesPanelStop = .half
    @State private var selectedPlaceId: UUID?
    @State private var selectedHintId: UUID?
    @State private var showsBeta = false
    /// Поиск — МОДАЛЬНОЕ состояние вкладки (10 и 11), а не поле внутри
    /// списка: фокус поднимает панель в полный список, гасит заголовок
    /// вкладки и кладёт на карту скрим. Выход один — «Отмена» (или тап по
    /// скриму): она снимает фокус, чистит запрос и возвращает панель туда,
    /// откуда пришли.
    @State private var searching = false
    @State private var stopBeforeSearch: PlacesPanelStop = .list
    @FocusState private var searchFocused: Bool
    /// Тот же монитор, что у «Ленты» (`CacheManager.shared`), а не свой:
    /// второй `NWPathMonitor` — это вторая подписка на путь сети ради
    /// одного булева.
    @ObservedObject private var network = CacheManager.shared.networkMonitor
    /// Тот же ключ, что у таб-бара: с пустого экрана единственная кнопка
    /// уводит на запись, а не открывает «как это работает» ещё раз.
    @AppStorage(AppTab.storageKey) private var selectedTab: AppTab = .home

    /// Меньше трёх мест — экран ещё не умеет рассказать о себе сам, и
    /// карточка «как это работает» стоит своего места. Подсказки её
    /// отменяют: они объясняют то же самое делом.
    private var showsHowItWorks: Bool { model.items.count < 3 && model.knownSuggestions.isEmpty }
    private var showsControls: Bool { model.items.count >= PlacesPresentation.manyPlaces }
    private var groups: [PlacesPresentation.Group] {
        PlacesPresentation.build(model.items, query: query, sort: sort, language: lang.language)
    }

    /// Совпадения поиска — БЕЗ группировки: заголовок секции над выдачей
    /// отвечал бы на вопрос, которого никто не задавал (спека §6, состояние
    /// 10). Порядок при этом остаётся выбранный: чипы никуда не делись.
    private var searchMatches: [PlaceListItem] {
        PlacesPresentation.sort(
            PlacesPresentation.filter(model.items, query: query, language: lang.language),
            by: sort
        )
    }

    private var searchOutcome: PlacesSearchOutcome {
        PlacesSearchOutcome.resolve(query: query, matches: searchMatches.count)
    }

    var body: some View {
        NavigationStack(path: $path) {
            stage(slot)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: PlacesDest.self) { dest in
                    switch dest {
                    case .place(let id):
                        // Таб-бар ОСТАЁТСЯ — так рисует макет S4 и так же
                        // ведут себя гараж и паспорт машины: экран места это
                        // лист внутри своей вкладки, а не отдельное место.
                        PlaceDetailView(placeId: id, onOpenTrip: { push(.trip($0, focus: $1)) })
                    case .trip(let id, let focus):
                        TripDetailView(tripId: id,
                                       viewModel: TripsViewModel(tripManager: mapVM.tripManager),
                                       focus: focus)
                    }
                }
        }
        // Клавиатура НЕ двигает вкладку, и снимать это надо у САМОГО
        // ВЕРХНЕГО вида, а не внутри.
        //
        // Панель стоит смещением от края экрана, а безопасную зону под
        // клавиатуру SwiftUI добавляет корню — и вся вкладка уезжала вверх
        // на её высоту: поле поиска ложилось на часы и на значок батареи.
        // Две попытки снять это ниже по дереву (у `ZStack` сцены и у самой
        // панели) не дали ничего — оба уже внутри сдвинутого контейнера.
        // Поймано кадром на симуляторе, не сборкой.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $showsBeta) {
            AtlasBetaSheet(model: .make(.places), onDismiss: { showsBeta = false })
                .contentSizedSheet(background: AppTheme.colors(for: scheme).card)
        }
        .task { model.reload() }
        .onChange(of: sort) { _, value in value.save() }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToPlace)) { note in
            guard let id = note.object as? UUID else { return }
            path = [.place(id)]
        }
    }

    /// Геометрия панели — из `WindowLayoutMetrics`, снимка окна ПОСЛЕ
    /// разметки UIKit. Не из `GeometryReader`: внутри безопасной зоны тот
    /// отдаёт её отступы нулями, и панель встаёт на сотню точек выше. И не из
    /// живого `UIWindow` в `body` — он однажды зациклил разметку «Атласа».
    private var slot: PlacesSlot {
        let metrics = WindowLayoutMetrics.shared
        let size = metrics.size ?? CGSize(width: 390, height: 844)
        let insets = metrics.safeAreaInsets ?? UIEdgeInsets(top: 47, left: 0, bottom: 34, right: 0)
        return PlacesSlot(height: size.height, safeTop: insets.top, safeBottom: insets.bottom)
    }

    /// Карта во всю высоту, панель поверх неё. Больше на вкладке ничего нет:
    /// заголовок, переключатель, поиск и порядок живут ВНУТРИ панели.
    private func stage(_ slot: PlacesSlot) -> some View {
        ZStack {
            map(interactive: true)
                .ignoresSafeArea()
            if network.isOffline { offlineCaption(slot) }
            if searching { searchScrim }
            panel(slot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Клавиатура НЕ двигает панель.
        //
        // Иначе SwiftUI поднимает всё содержимое над ней, и панель, чей верх
        // считается от безопасной зоны (`зона + 56`), уезжает ПОД ЧАСЫ —
        // поле поиска ложится на время и на значок батареи (поймано кадром на
        // симуляторе). Панель стоит там же, где стояла; клавиатура просто
        // накрывает её низ, ровно как рисует матрица состояний.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: emptyState) { _, state in
            // Во время поиска панель держит полный список и чужим правкам
            // не подчиняется: место, приехавшее пулом, не имеет права
            // уронить панель из-под пальца, который набирает запрос.
            guard !searching else { return }
            withAnimation(SlotGesture.spring) { stop = state.stop(in: slot) }
        }
        .onAppear {
            if emptyState.isPinned { stop = emptyState.stop(in: slot) }
            else if !stop.isDraggable { stop = slot.defaultStop }
        }
        // Фокус в поле И ЕСТЬ вход в поиск. Обратное неверно: потеря фокуса
        // (скролл гасит клавиатуру) поиск не закрывает — иначе один
        // неосторожный свайп стирал бы набранный запрос.
        .onChange(of: searchFocused) { _, focused in
            if focused { beginSearch() }
        }
    }

    /// Пустая вкладка (13, 14, 15). Подсказки в этот вопрос НЕ входят: до
    /// 0.8.2 входили, и вкладка без мест, но с подсказками уходила в
    /// половину вместо пустой — подсказка отменяла пустоту, хотя мест от неё
    /// не появлялось.
    private var emptyState: PlacesEmptyState {
        PlacesEmptyState.resolve(places: model.items.count, trips: model.recentTrips.count)
    }

    /// Скрим 38 % под поиском (10 и 11). Он же второй выход: палец, ушедший
    /// мимо «Отмены», не должен упираться в экран, с которого не выйти.
    private var searchScrim: some View {
        AtlasTheme.scrim
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { endSearch() }
            .transition(.opacity)
            // Скрим ГЛУХОЙ для VoiceOver, иначе ротор уходит на карту под
            // ним — то же правило, что у `AppConfirmDialog`.
            .accessibilityHidden(true)
    }

    /// «Карта появится, когда будет сеть» (24) — по СЕРЕДИНЕ видимой карты, а
    /// не у верхнего края: видимая полоска меняется от 56 pt в списке до
    /// целого экрана в положении «Карта», и подпись у края читалась бы
    /// системным баннером в одном случае и потерянной строкой в другом.
    private func offlineCaption(_ slot: PlacesSlot) -> some View {
        let visible = max(0, (liveTop ?? slot.top(of: stop)) - slot.safeTop)
        return VStack(spacing: 0) {
            Text(AppStrings.placesOfflineMap(lang.language))
                .font(AppType.caption)
                .foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: visible)
            Spacer(minLength: 0)
        }
        // Подпись не перехватывает тапы: под ней карта с булавками, и они
        // остаются на месте — сеть отменяет плитки, а не места.
        .allowsHitTesting(false)
        .accessibilityIdentifier("places_offline_note")
    }

    private func panel(_ slot: PlacesSlot) -> some View {
        PlacesPanel(
            slot: slot,
            stop: $stop,
            liveTop: $liveTop,
            isPinned: emptyState.isPinned || searching,
            accessibilityTitle: AppStrings.tabPlaces(lang.language),
            header: {
                // Заголовок вкладки на время поиска СКРЫТ (состояния 10 и
                // 11): человек ищет место, а не читает, на какой он вкладке,
                // и переключатель «Список · Карта» ему сейчас некуда вести.
                if !searching {
                    PlacesPanelHeader(
                        title: AppStrings.tabPlaces(lang.language),
                        listTitle: AppStrings.placesViewList(lang.language),
                        mapTitle: AppStrings.placesViewMap(lang.language),
                        stop: stop,
                        onBeta: { showsBeta = true },
                        onList: { move(to: .list) },
                        onMap: { move(to: .map) }
                    )
                }
            },
            content: { panelContent }
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Переключатель не меняет экраны — он двигает панель (спека §3.2).
    private func move(to target: PlacesPanelStop) {
        clearSelection()
        withAnimation(SlotGesture.spring) {
            stop = target
            liveTop = nil
        }
    }

    /// Тап по булавке МЕНЯЕТ СОДЕРЖИМОЕ ПАНЕЛИ, а не открывает экран
    /// (состояния 5 и 6). Экран места открывает строка в панели — так у
    /// человека остаётся шаг назад, и промах по булавке не уносит его со
    /// вкладки.
    ///
    /// Для подсказки это НОВОЕ поведение: раньше тап по пунктирной булавке не
    /// делал ничего, потому что открывать было нечего. Теперь открывать есть
    /// что — карточку с «Сохранить как место».
    private func select(pin id: UUID) {
        let isPlace = model.items.contains { $0.id == id }
        let isHint = model.knownSuggestions.contains { $0.id == id }
        guard isPlace || isHint else { return }
        if stop.isDraggable { stopBeforeSelection = stop }
        withAnimation(SlotGesture.spring) {
            selectedPlaceId = isPlace ? id : nil
            selectedHintId = isPlace ? nil : id
            stop = isPlace ? .selectedPlace : .selectedHint
            liveTop = nil
        }
    }

    private func clearSelection() {
        selectedPlaceId = nil
        selectedHintId = nil
    }

    @ViewBuilder
    private var panelContent: some View {
        if searching {
            searchContent
        } else {
            stopContent
        }
    }

    @ViewBuilder
    private var stopContent: some View {
        switch stop {
        case .map:
            // Только заголовок: карта во всю высоту.
            EmptyView()
        case .selectedPlace, .selectedHint:
            selectionContent
        case .empty:
            emptyContent
        case .half:
            halfContent
        case .list:
            listContent
        }
    }

    /// Половина: список без скролла. Скролл начинается в полном списке —
    /// иначе жест по содержимому спорил бы с жестом панели.
    @ViewBuilder
    private var halfContent: some View {
        VStack(spacing: 12) {
            lastPassSection
            placesSection
            suggestionsSection
        }
        .padding(.top, 4)
    }

    /// Поиск (10 и 11): поле с «Отменой» закреплено, результаты строками
    /// сразу под ним. Заголовка секции нет, чипов порядка нет — экран сейчас
    /// отвечает на один вопрос, и лишние контролы над ответом только мешают.
    @ViewBuilder
    private var searchContent: some View {
        VStack(spacing: 12) {
            searchRow(cancellable: true)
            if searchOutcome == .nothingFound {
                nothingFoundBlock
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(searchMatches) { item in
                            PlaceCardView(item: item, compact: true) { push(.place(item.id)) }
                        }
                    }
                    .padding(.horizontal, 16)
                    // Клавиатуру `ContentView` гасит для всего окна
                    // (`.ignoresSafeArea(.keyboard)`), поэтому нижние строки
                    // достаются из-под неё ЧИСЛОМ — как и высоты панели.
                    .padding(.bottom, Self.keyboardClearance)
                    .accessibilityIdentifier("places_search_results")
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .padding(.top, 4)
    }

    /// Клавиатура спеки §9: 291 pt на всех телефонах кроме SE (260). Берём
    /// больший — лишний воздух под последней строкой не мешает, а нехватка
    /// прячет строку насовсем.
    private static let keyboardClearance: CGFloat = 291

    /// Состояние 11. Кнопок нет ни одной нарочно: «Отмена» уже стоит у поля,
    /// а вторая дорога к тому же результату — это выбор там, где его нет.
    private var nothingFoundBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(AtlasTheme.chip)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(AtlasTheme.secondary)
            }
            .frame(width: 56, height: 56)
            Text(AppStrings.placesSearchEmpty(lang.language))
                .font(AppType.itemTitle)
                .foregroundStyle(AtlasTheme.ink)
            Text(AppStrings.placesSearchEmptyHint(lang.language))
                .font(AppType.body)
                .foregroundStyle(AtlasTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("places_search_empty")
    }

    /// Фокус в поле — это переход в состояние 10, а не «начал печатать».
    private func beginSearch() {
        guard !searching else { return }
        stopBeforeSearch = stop.isDraggable ? stop : .list
        withAnimation(SlotGesture.animation(reduceMotion: reduceMotion)) {
            searching = true
            stop = .list
            liveTop = nil
        }
        // Фокус ставится ПОВТОРНО, и это не подстраховка.
        //
        // Поле поиска до входа и после — физически РАЗНЫЕ `TextField`: список
        // и состояние поиска это разные поддеревья, и SwiftUI пересоздаёт
        // поле вместе с его `@FocusState`. Фокус уходит в никуда, клавиатура
        // не приезжает вовсе, и человек видит открывшийся поиск, в котором
        // нечем набрать (поймано кадром на симуляторе, а не сборкой).
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard searching else { return }
            searchFocused = true
        }
    }

    /// «Отмена» (и тап по скриму): снимает фокус, ЧИСТИТ запрос и возвращает
    /// панель туда, откуда пришли (спека: «Отмена» → 7).
    private func endSearch() {
        searchFocused = false
        withAnimation(SlotGesture.animation(reduceMotion: reduceMotion)) {
            searching = false
            query = ""
            stop = stopBeforeSearch
            liveTop = nil
        }
    }

    @ViewBuilder
    private var listContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if showsControls {
                    searchRow(cancellable: false)
                    sortChips
                }
                lastPassSection
                placesSection
                suggestionsSection
            }
            .padding(.top, 4)
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    /// «Последний проезд» — ответ вкладки на «зачем сюда возвращаться».
    ///
    /// Показывается редко и по границам `PlaceLastPass`: не меньше пяти минут
    /// и не меньше десятой доли медианы, внутри одного направления, с медианой
    /// от трёх проездов. Находка обязана остаться находкой — «быстрее на
    /// минуту» после каждой поездки обесценило бы её за неделю.
    @ViewBuilder
    private var lastPassSection: some View {
        if let reading = model.lastPass,
           let item = model.items.first(where: { $0.id == reading.placeId }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placeLastPassSection(lang.language))
                    .atlasSectionStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("places_last_pass")
                Button {
                    Haptics.tap()
                    model.markLastPassSeen()
                    push(.place(reading.placeId))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AtlasTheme.accentInk)
                            .frame(width: 40, height: 40)
                            .background(AtlasTheme.accentSoft, in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.place.name ?? AppStrings.placeUnnamed(lang.language))
                                .font(AppType.itemTitle)
                                .foregroundStyle(AtlasTheme.ink)
                                .lineLimit(1)
                            Text(lastPassLine(reading))
                                .font(AppType.meta)
                                .foregroundStyle(AtlasTheme.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 64)
                    .background(AtlasTheme.card,
                                in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableCardStyle())
                .accessibilityIdentifier("places_last_pass_row")
            }
            .padding(.horizontal, 16)
        }
    }

    /// «Вчера · на 7 мин быстрее обычного». «Дольше» — теми же словами и тем
    /// же цветом: это наблюдение, а не провал.
    private func lastPassLine(_ reading: PlaceLastPass.Reading) -> String {
        let l = lang.language
        let when = RelativeTripDate.string(from: reading.at, language: l)
        let delta = CheckpointReading.clock(reading.delta, lang: l)
        return reading.isFaster
            ? AppStrings.placeLastPassFaster(l, when: when, delta: delta)
            : AppStrings.placeLastPassSlower(l, when: when, delta: delta)
    }

    @ViewBuilder
    private var emptyContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                suggestionsSection
                noPlacesNote
                markInTripSection
            }
            .padding(.top, 4)
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
    }

    /// Выбранная на карте булавка: одна строка или одна карточка и крестик.
    @ViewBuilder
    private var selectionContent: some View {
        if let id = selectedPlaceId, let item = model.items.first(where: { $0.id == id }) {
            HStack(spacing: 8) {
                PlaceCardView(item: item, compact: true) { push(.place(id)) }
                closeButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        } else if let id = selectedHintId,
                  let hint = model.knownSuggestions.first(where: { $0.id == id }) {
            HStack(alignment: .top, spacing: 8) {
                PlaceSuggestionCardView(suggestion: hint) { model.save(hint) }
                closeButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.tap()
            withAnimation(SlotGesture.spring) {
                clearSelection()
                stop = stopBeforeSelection
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AtlasTheme.secondary)
                .frame(width: 36, height: 36)
                .background(AtlasTheme.chip, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.close(lang.language))
        .accessibilityIdentifier("places_selection_close")
    }

    /// Идемпотентный push — быстрый двойной тап по одной и той же булавке
    /// или карточке не должен класть в стек два экземпляра одного экрана.
    private func push(_ dest: PlacesDest) {
        guard path.last != dest else { return }
        path.append(dest)
    }

    private func openLastTrip() {
        guard let id = model.lastTripId else { return }
        push(.trip(id, focus: .top))
    }

    private func searchRow(cancellable: Bool) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AtlasTheme.secondary)
                TextField(AppStrings.placesSearchPlaceholder(lang.language), text: $query)
                    .font(AppType.body)
                    .foregroundStyle(AtlasTheme.ink)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("places_search")
                if !query.isEmpty {
                    Button {
                        query = ""
                        Haptics.tap()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(AtlasTheme.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.calendarClearFilter(lang.language))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(AtlasTheme.searchBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if cancellable {
                Button {
                    Haptics.tap()
                    endSearch()
                } label: {
                    Text(AppStrings.cancel(lang.language))
                        .font(AppType.action)
                        .foregroundStyle(AtlasTheme.accent)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("places_search_cancel")
            }
        }
        .padding(.horizontal, 16)
    }

    /// Порядок — ЧИПАМИ, а не листом (спека §3.4).
    ///
    /// Лист прятал три коротких слова за двумя нажатиями и модальным экраном;
    /// здесь выбор виден целиком и меняется одним тапом, а активный чип ещё и
    /// отвечает на «в каком порядке я сейчас смотрю».
    private var sortChips: some View {
        HStack(spacing: 8) {
            ForEach(PlacesSort.allCases, id: \.self) { order in
                sortChip(order)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func sortChip(_ order: PlacesSort) -> some View {
        let active = sort == order
        return Button {
            Haptics.tap()
            searchFocused = false
            withAnimation(.snappy(duration: 0.22)) { sort = order }
        } label: {
            Text(title(for: order))
                .font(active ? AppType.chipActive : AppType.chip)
                .foregroundStyle(active ? AtlasTheme.background : AtlasTheme.ink)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(active ? AtlasTheme.ink : AtlasTheme.chip, in: Capsule())
                // Нарисован 32, палец получает 44 (спека §7).
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("places_sort_\(order.rawValue)")
    }

    private func title(for order: PlacesSort) -> String {
        switch order {
        case .recent: return AppStrings.placesSortRecent(lang.language)
        case .frequent: return AppStrings.placesSortFrequent(lang.language)
        case .name: return AppStrings.placesSortName(lang.language)
        }
    }

    // MARK: - Карта

    /// Булавки мест И подсказок на ОДНОЙ карте: вторую заводить нельзя,
    /// `PlacesMapView` умеет несколько булавок и подбирает область по всем.
    private var pins: [PlacePin] {
        model.items.map { PlacePin(id: $0.id, coordinate: $0.place.coordinate) }
            + model.knownSuggestions.map { PlacePin(id: $0.id, coordinate: $0.coordinate, isSuggested: true) }
    }

    private func map(interactive: Bool) -> some View {
        PlacesMapView(pins: pins,
                      // Превью живёт внутри скролла: с живыми жестами палец,
                      // начатый на карте, панорамирует её вместо того чтобы
                      // скроллить список. Тап по булавке от этого не страдает.
                      isInteractive: interactive,
                      isOffline: network.isOffline,
                      onPinTap: { tapped in select(pin: tapped) })
    }

    /// Превью со «стеклянной» кнопкой «Карта» в углу — она и есть вход в
    /// режим карты, когда переключателя ещё нет.
    // MARK: - Список

    @ViewBuilder
    private var placesSection: some View {
        let built = groups
        if built.isEmpty {
            // Пустой выдачи поиска здесь больше НЕТ: поиск стал модальным
            // состоянием панели (10 и 11) и рисует свой `nothingFoundBlock`,
            // а «Отмена» чистит запрос на выходе — то есть в этой ветке
            // `query` всегда пуст. Двух «Ничего не нашлось» с одним
            // идентификатором быть не должно.
            if model.items.isEmpty {
                // Мест нет, но подсказки есть (S3): заголовок секции здесь
                // был бы заголовком над пустотой.
                VStack(spacing: 6) {
                    Text(AppStrings.placesNoneYet(lang.language))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                    Text(AppStrings.placesNoneYetBody(lang.language))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("places_none_yet")
            }
        } else {
            LazyVStack(spacing: 12) {
                ForEach(built) { group in
                    sectionHeader(for: group, total: built.count)
                    ForEach(group.items) { item in
                        PlaceCardView(item: item, compact: showsControls) { push(.place(item.id)) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("places_list")
        }
    }

    @ViewBuilder
    private func sectionHeader(for group: PlacesPresentation.Group, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(groupTitle(group))
                .atlasSectionStyle()
            Spacer(minLength: 0)
            Text("\(AppStrings.formattedCount(group.items.count, lang: lang.language))")
                .font(AppType.meta)
                .foregroundStyle(AtlasTheme.secondary)
        }
        .padding(.top, total > 1 ? 6 : 0)
    }

    private func groupTitle(_ group: PlacesPresentation.Group) -> String {
        switch group.kind {
        case .all: return AppStrings.placesMineSection(lang.language)
        // Относительные даты берём УЖЕ переведённые: спека прямо запрещает
        // заводить под них новые ключи.
        case .today: return AppStrings.today(lang.language)
        case .thisWeek: return AppStrings.thisWeek(lang.language)
        case .earlier: return AppStrings.earlier(lang.language)
        case .frequent: return AppStrings.placesGroupFrequent(lang.language)
        case .others: return AppStrings.placesGroupOthers(lang.language)
        }
    }

    /// «Похоже, вы здесь бываете» — и СКЕЛЕТОН, пока подсказки считаются
    /// (состояние 23). «Мои места» читаются из базы мгновенно, а подсказки
    /// разбирают превью всей библиотеки вне главного актёра и приезжают
    /// позже: без скелетона блок появлялся рывком под уже прочитанным
    /// списком. Других скелетонов на вкладке нет и быть не должно — места
    /// локальные, «загружать» тут нечего.
    @ViewBuilder
    private var suggestionsSection: some View {
        if query.isEmpty {
            if model.isComputingSuggestions {
                suggestionsBlock {
                    SkeletonPlaceholder(shape: .placeSuggestion, count: 1)
                        .accessibilityLabel(AppStrings.placesSuggestLoading(lang.language))
                        .accessibilityIdentifier("places_suggestions_skeleton")
                }
            } else if !model.knownSuggestions.isEmpty {
                suggestionsBlock {
                    ForEach(model.knownSuggestions) { suggestion in
                        PlaceSuggestionCardView(suggestion: suggestion) { model.save(suggestion) }
                    }
                }
            }
        }
    }

    private func suggestionsBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.placeSuggestSection(lang.language))
                .atlasSectionStyle()
                .frame(maxWidth: .infinity, alignment: .leading)
                // Идентификатор — на ЗАГОЛОВКЕ, не на колонке: на
                // контейнере он достаётся и строкам внутри, и каждая
                // подсказка теряет своё имя (`place_suggestion_<ячейка>`).
                .accessibilityIdentifier("places_suggestions")
            content()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Пусто

    /// «Мест пока нет» — строка-объяснение над подсказками (S3).
    ///
    /// Нужна ровно в одном состоянии: подсказка уже есть, а места ещё нет, и
    /// без этой строки экран открывался карточкой «Сохранить как место» без
    /// единого слова о том, куда она сохранится.
    private var noPlacesNote: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(AtlasTheme.chip)
                Image(systemName: "mappin.slash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AtlasTheme.secondary)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppStrings.placesNoneYet(lang.language))
                    .font(AppType.itemTitle)
                    .foregroundStyle(AtlasTheme.ink)
                Text(AppStrings.placesNoneYetBody(lang.language))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("places_no_places_note")
    }

    /// «Отметить в поездке» — последние поездки, куда можно поставить отметку
    /// руками (S3). Место рождается ИЗ ОТМЕТКИ (правило 0.6.8), а отметку
    /// ставят на экране поездки — значит у вкладки без мест обязана быть
    /// дорога туда, иначе она рассказывает про механику, до которой отсюда
    /// не дойти.
    @ViewBuilder
    private var markInTripSection: some View {
        if !model.recentTrips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placesMarkInTrip(lang.language))
                    .atlasSectionStyle()
                    .padding(.horizontal, 16)
                VStack(spacing: 0) {
                    ForEach(Array(model.recentTrips.enumerated()), id: \.element.id) { index, trip in
                        if index > 0 { AtlasTheme.separator.frame(height: 1) }
                        tripRow(trip)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
                .background(AtlasTheme.card, in: RoundedRectangle(cornerRadius: AtlasTheme.cardRadius, style: .continuous))
                .padding(.horizontal, 16)
            }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
        let l = lang.language
        return Button {
            Haptics.tap()
            push(.trip(trip.id, focus: .top))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.title ?? tripDate(trip, l))
                        .font(AppType.itemTitle)
                        .foregroundStyle(AtlasTheme.ink)
                        .lineLimit(1)
                    Text(tripSubtitle(trip, l))
                        .font(AppType.meta)
                        .foregroundStyle(AtlasTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AtlasTheme.secondary.opacity(0.7))
            }
            .padding(.vertical, 7)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityIdentifier("places_trip_row")
    }

    /// «24 сент. · 55 мин · 68 км». Расстояние — только через `Measure`, с
    /// явной единицей: второго способа напечатать километры в этом
    /// приложении нет (правило 0.6.7).
    private func tripSubtitle(_ trip: Trip, _ l: LanguageManager.Language) -> String {
        // Без заголовка датой названа сама строка — повторять её в подписи
        // значит напечатать одно и то же дважды подряд.
        let date = trip.title == nil ? "" : tripDate(trip, l)
        let time = CheckpointReading.clock(trip.duration, lang: l)
        let distance = Measure.distance(metres: trip.distance, unit: distanceUnit, lang: l)
        return [date, time, distance].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func tripDate(_ trip: Trip, _ l: LanguageManager.Language) -> String {
        Self.tripDayMonth[l]?.string(from: trip.startDate) ?? ""
    }

    private static let tripDayMonth = LocalizedDateFormatter.templates("dMMM")

    private func startRecording() {
        selectedTab = .record
    }
}

/// Направления стека «Мест». Типизирован, как `MeDest`: ссылка с чужим
/// значением здесь была бы мертва.
enum PlacesDest: Hashable {
    case place(UUID)
    case trip(UUID, focus: TripFocus)
}
