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
    @StateObject private var model = PlacesTabViewModel()
    @State private var path: [PlacesDest] = []
    @State private var query = ""
    @State private var sort = PlacesSort.load()
    @State private var showsSort = false
    @State private var showsMap = false
    @State private var showsBeta = false
    @FocusState private var searchFocused: Bool
    /// Тот же ключ, что у таб-бара: с пустого экрана единственная кнопка
    /// уводит на запись, а не открывает «как это работает» ещё раз.
    @AppStorage(AppTab.storageKey) private var selectedTab: AppTab = .home

    /// Меньше трёх мест — экран ещё не умеет рассказать о себе сам, и
    /// карточка «как это работает» стоит своего места. Подсказки её
    /// отменяют: они объясняют то же самое делом.
    private var showsHowItWorks: Bool { model.items.count < 3 && model.suggestions.isEmpty }
    private var showsControls: Bool { model.items.count >= PlacesPresentation.manyPlaces }
    private var groups: [PlacesPresentation.Group] {
        PlacesPresentation.build(model.items, query: query, sort: sort, language: lang.language)
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .background(AtlasTheme.background.ignoresSafeArea())
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
        .sheet(isPresented: $showsSort) { sortSheet }
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

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty && model.suggestions.isEmpty {
            emptyState
        } else if showsMap {
            mapMode
        } else {
            list
        }
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

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Значок «Бета» — ВПЛОТНУЮ к заголовку (зазор 6), как на
            // «Атласе»: он подпись к слову «Места», а не отдельный контрол.
            HStack(spacing: 6) {
                Text(AppStrings.tabPlaces(lang.language))
                    .font(AppType.title)
                    .tracking(AppType.titleTracking)
                    .foregroundStyle(AtlasTheme.ink)
                AtlasBetaChip(action: { showsBeta = true }, identifier: "places_beta_chip")
            }
            Spacer(minLength: 0)
            if showsControls {
                Text(AppStrings.placesCount(lang.language, count: model.items.count))
                    .font(AppType.meta)
                    .foregroundStyle(AtlasTheme.secondary)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
    }

    /// Список / Карта. Появляется только вместе с остальными контролами:
    /// у пяти мест карта и так стоит первой строкой экрана.
    private var modeSwitch: some View {
        HStack(spacing: 2) {
            modeButton(title: AppStrings.placesViewList(lang.language),
                       symbol: "list.bullet", active: !showsMap) { showsMap = false }
            modeButton(title: AppStrings.placesViewMap(lang.language),
                       symbol: "map", active: showsMap) { showsMap = true }
        }
        .padding(3)
        .background(AtlasTheme.searchBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func modeButton(title: String, symbol: String, active: Bool,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            searchFocused = false
            withAnimation(.snappy(duration: 0.22)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                Text(title).font(active ? AppType.chip : AppType.body)
            }
            .foregroundStyle(active ? AtlasTheme.ink : AtlasTheme.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AtlasTheme.card)
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
        .accessibilityIdentifier("places_mode_\(symbol == "map" ? "map" : "list")")
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
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

            Button {
                Haptics.tap()
                searchFocused = false
                showsSort = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .medium))
                    Text(sortTitle).font(AppType.chip)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(AtlasTheme.ink)
                .padding(.leading, 10).padding(.trailing, 12)
                .frame(height: 44)
                .background(AtlasTheme.card, in: Capsule())
                .overlay(Capsule().stroke(AtlasTheme.separator, lineWidth: 1))
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityIdentifier("places_sort")
        }
        .padding(.horizontal, 16)
    }

    private var sortTitle: String {
        switch sort {
        case .recent: return AppStrings.placesSortRecent(lang.language)
        case .frequent: return AppStrings.placesSortFrequent(lang.language)
        case .name: return AppStrings.placesSortName(lang.language)
        }
    }

    private var sortSheet: some View {
        SettingsOptionPicker(
            title: AppStrings.placesSortTitle(lang.language),
            options: PlacesSort.allCases,
            selection: sort,
            footnote: "",
            badge: { option in
                switch option {
                case .recent: return "clock"
                case .frequent: return "flame"
                case .name: return "textformat.abc"
                }
            },
            badgeIsSymbol: true,
            label: { option in
                switch option {
                case .recent: return AppStrings.placesSortRecent(lang.language)
                case .frequent: return AppStrings.placesSortFrequent(lang.language)
                case .name: return AppStrings.placesSortName(lang.language)
                }
            },
            onSelect: { option in
                sort = option
                showsSort = false
            },
            accessibilityPrefix: "places_sort_option"
        )
        .contentSizedSheet(background: AtlasTheme.background)
    }

    // MARK: - Карта

    /// Булавки мест И подсказок на ОДНОЙ карте: вторую заводить нельзя,
    /// `PlacesMapView` умеет несколько булавок и подбирает область по всем.
    private var pins: [PlacePin] {
        model.items.map { PlacePin(id: $0.id, coordinate: $0.place.coordinate) }
            + model.suggestions.map { PlacePin(id: $0.id, coordinate: $0.coordinate, isSuggested: true) }
    }

    private func map(interactive: Bool) -> some View {
        PlacesMapView(pins: pins,
                      // Превью живёт внутри скролла: с живыми жестами палец,
                      // начатый на карте, панорамирует её вместо того чтобы
                      // скроллить список. Тап по булавке от этого не страдает.
                      isInteractive: interactive,
                      onPinTap: { tapped in
                          // Подсказка — ещё не экран: у неё нет ни истории,
                          // ни проездов. Открываем только место.
                          guard model.items.contains(where: { $0.id == tapped }) else { return }
                          push(.place(tapped))
                      })
    }

    /// Превью со «стеклянной» кнопкой «Карта» в углу — она и есть вход в
    /// режим карты, когда переключателя ещё нет.
    private var mapCard: some View {
        map(interactive: false)
            .frame(height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Button {
                    Haptics.tap()
                    withAnimation(.snappy(duration: 0.22)) { showsMap = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                        Text(AppStrings.placesViewMap(lang.language)).font(AppType.body)
                    }
                    .foregroundStyle(AtlasTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(AtlasTheme.card.opacity(0.94), in: Capsule())
                }
                .buttonStyle(PressableCardStyle())
                .padding(10)
                .accessibilityIdentifier("places_open_map")
            }
            .padding(.horizontal, 16)
    }

    private var mapMode: some View {
        VStack(spacing: 12) {
            header
            modeSwitch
            map(interactive: true)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, CustomTabBar.clearance)
        }
        .padding(.top, 2)
    }

    // MARK: - Список

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if showsControls {
                    modeSwitch
                    searchRow
                }
                if !showsControls || query.isEmpty { mapCard }
                if model.items.isEmpty { noPlacesNote }
                placesSection
                suggestionsSection
                markInTripSection
                if showsHowItWorks {
                    PlacesHowItWorksCard(onOpenLastTrip: model.lastTripId == nil ? nil : openLastTrip,
                                         onStartRecording: startRecording)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, CustomTabBar.clearance)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        // Как лента: скролл до физического низа, клиренс — от него.
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private var placesSection: some View {
        let built = groups
        if built.isEmpty {
            if !query.isEmpty {
                Text(AppStrings.placesSearchEmpty(lang.language))
                    .font(AppType.body)
                    .foregroundStyle(AtlasTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .accessibilityIdentifier("places_search_empty")
            } else if model.items.isEmpty {
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
        case .frequent: return AppStrings.placesGroupFrequent(lang.language)
        case .others: return AppStrings.placesGroupOthers(lang.language)
        }
    }

    @ViewBuilder
    private var suggestionsSection: some View {
        if !model.suggestions.isEmpty, query.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(AppStrings.placeSuggestSection(lang.language))
                    .atlasSectionStyle()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Идентификатор — на ЗАГОЛОВКЕ, не на колонке: на
                    // контейнере он достаётся и строкам внутри, и каждая
                    // подсказка теряет своё имя (`place_suggestion_<ячейка>`).
                    .accessibilityIdentifier("places_suggestions")
                ForEach(model.suggestions) { suggestion in
                    PlaceSuggestionCardView(suggestion: suggestion) { model.save(suggestion) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
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

    /// Пустая вкладка (S2): что это такое, как выглядит и что нажать.
    ///
    /// Иллюстрации-заглушки здесь больше нет. Она честно говорила «пусто», но
    /// на вопрос «а что тут бывает» не отвечала ничем — а именно его и задаёт
    /// человек, открывший вкладку в первый раз («не очень ощущение, что экран
    /// «Места» пустой какой-то», владелец 20 сен).
    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(AppStrings.placesEmptyIntro(lang.language))
                    .font(AppType.body)
                    .foregroundStyle(AtlasTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, -4)
                PlacesHowItWorksCard(onOpenLastTrip: model.lastTripId == nil ? nil : openLastTrip,
                                     onStartRecording: startRecording)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 2)
            .padding(.bottom, CustomTabBar.clearance)
            // `.contain`, не по умолчанию: без своего контейнера SwiftUI
            // отдаёт идентификатор вниз по немаркированным обёрткам и не
            // заводит элемент, по которому экран можно найти (та же ловушка,
            // что у `place_detail`).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("places_empty")
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        // Тот же приём, что у `list`: без него центр сцены считается от края
        // safe area, а не от физического низа, и стоит выше пилюли.
        .ignoresSafeArea(edges: .bottom)
    }

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
