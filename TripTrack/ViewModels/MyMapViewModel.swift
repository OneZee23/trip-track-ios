import Foundation
import MapKit
import SwiftUI

/// Data source for the 0.6.0 «Моя карта» screen (Figma page «🧭 Карта»).
///
/// The canon note on that page sets the model: one free-pan map where the
/// territory and the trips live in the SAME layer — «слоёв-переключателей
/// нет» — and everything on it is tappable, with a permanent sheet that
/// swaps its contents to whatever you touched.
///
/// So this VM holds two things: the exploration (built once from CoreData +
/// the bundled `RegionAtlas`) and the current selection, which is what the
/// sheet and the highlighted overlay both read.
@MainActor
final class MyMapViewModel: ObservableObject {
    /// App-scoped singleton: the Maps tab view is destroyed on every tab
    /// switch (ContentView renders tabs in a switch), so a view-owned
    /// @StateObject would re-run the full CoreData + attribution pass on
    /// every visit.
    static let shared = MyMapViewModel()

    /// What the sheet is currently showing. `nil` = the collapsed summary.
    ///
    /// «Закрытого» региона здесь больше нет (0.7.0). Туман не показывает
    /// границ того, чего ты не видел: непосещённого региона на карте нет
    /// вовсе — ни контура, ни пунктира, ни карточки «ещё не открыт», — а
    /// значит и выбрать его нечем.
    enum Selection: Equatable {
        case region(String)         // atlas region id, opened
        case trip(UUID)
        /// Печать находки (0.7.0). Несёт `Discovery.id`, а не саму находку:
        /// список печатей перечитывается на каждое `.discoveriesChanged`, и
        /// выбор, державший копию, показывал бы вчерашнюю дату.
        case discovery(UUID)
        /// Every trip that used the road under your finger, newest first.
        /// A street you drive daily belongs to a dozen trips, and handing back
        /// only the nearest one made the other eleven unreachable.
        case road([UUID])
    }

    @Published private(set) var isLoading = true
    @Published private(set) var exploration = MapExploration()
    /// Открытый мир, как он лежит в базе (0.7.0). Из него строятся ОБА
    /// оверлея — и дыра, и линия в ней, — поэтому разъехаться им нечем.
    @Published private(set) var revealed = RevealedLayer.empty
    /// Непрозрачный туман поверх всего мира.
    @Published private(set) var fogVeil: FogVeilOverlay?
    /// Тонкая тёплая линия по оси коридоров.
    @Published private(set) var routeVein: RouteVeinOverlay?
    /// Выбранная поездка — та же жилка, шире и светлее.
    ///
    /// Градиента скорости на Атласе больше нет: он был вторым, куда более
    /// ярким «страва-следом» прямо поверх коридора, ради снятия которого всё
    /// и затевалось. Заодно ушёл и единственный на этом экране поход за
    /// точками поездки — жилка рисуется по превью, которое уже в памяти.
    /// Градиент скорости остался там, где он отвечает на вопрос, — на экране
    /// поездки.
    @Published private(set) var selectedRoute: RouteVeinOverlay?
    /// Найденное — печати на карте. Читается из базы готовым, как и туман:
    /// разбирать треки «Атлас» не имеет права (это делает финиш поездки).
    @Published private(set) var seals: [Discovery] = []
    /// Не больше трёх нерешённых загадок, ближайших к открытому
    /// (`RiddleHint.plan`). Пусто, пока в каталоге ничего нет, — и это не
    /// поломка, а первый запуск до бандла.
    @Published private(set) var riddleHints: [RiddleHint] = []
    /// «Журнал первооткрывателя» — всё, что печатает развёрнутый лист.
    ///
    /// Считается ЗДЕСЬ (`JournalBuilder.build`), а не в `body`: лист
    /// перерисовывается на каждый кадр перетаскивания ручки, а в журнале и
    /// сортировка печатей, и расстояние от открытого до каждого круга.
    @Published private(set) var journal = Journal.empty
    /// Set through `select` / `selectRoad` only — the drawn route is kept in
    /// step from there, and a direct write would leave the two disagreeing.
    @Published private(set) var selection: Selection?
    /// One-shot camera command consumed by the map (`nil` once applied).
    @Published var cameraCommand: MapCameraCommand?
    /// Поездки выбранного региона, уже отсортированные.
    ///
    /// Считаются ОДИН раз на выбор и на смену данных, а не в `body`: лист
    /// перерисовывается на каждый кадр перетаскивания ручки, а внутри —
    /// выборка по id и сортировка. У региона с тысячей поездок это тысяча
    /// поисков и сортировка шестьдесят раз в секунду (CLAUDE.md: «вью-модели
    /// считают вне `body`»).
    @Published private(set) var selectedRegionTrips: [MapTripPin] = []

    /// Свои места на карте «Атласа» (макет S8). Серые — вне выбранного
    /// периода: место не перестаёт существовать оттого, что окно его не
    /// захватило, и убирать его значило бы соврать про карту.
    @Published private(set) var placePins: [AtlasPlacePin] = []
    /// Нажатая булавка места — под ней встаёт карточка. `nil` — карточки нет.
    @Published var selectedPlaceId: UUID?

    /// Метка дома. `nil` — дома нет ИЛИ человек снял «показывать на карте».
    ///
    /// Живёт ЗДЕСЬ, а не в `@State` экрана и не читается координатором из
    /// `HomeManager` напрямую, по той же причине, что стиль карты и период:
    /// до карты всё везёт подписка `Coordinator.bindViewModel`, а
    /// `updateUIViewController` на «Атласе» SwiftUI зовёт только на старте.
    /// Положи это мимо вью-модели — и метка просто не появится, молча.
    @Published private(set) var homePin: CLLocationCoordinate2D?

    /// «Вид карты»: стиль мглы, клетки и фото на карте.
    ///
    /// Живёт ЗДЕСЬ, а не в `@State` экрана, по той же причине, что камера и
    /// период: до карты выбор везёт подписка `Coordinator.bindViewModel`, а
    /// `updateUIViewController` SwiftUI на «Атласе» зовёт только на старте
    /// (замер 26 сентября). Пока стиль ехал ТОЛЬКО оттуда, он не доезжал
    /// вовсе: лист переставлял галочку, а карта оставалась в стартовом
    /// стиле — владелец на устройстве 27 сентября, три кадра трёх стилей
    /// совпали побайтово. Держит `AtlasAppearanceWiringTests`.
    @Published private(set) var appearance = AtlasMapAppearance.saved

    /// Выбор человека в листе «Вид карты». Сохраняется здесь же: у выбора
    /// одна дверь, и запоминать его отдельным `.onChange` на экране значило
    /// бы завести вторую.
    func setAppearance(_ value: AtlasMapAppearance) {
        guard value != appearance else { return }
        appearance = value
        value.save()
    }

    @Published private(set) var period: AtlasPeriod = .allTime
    @Published private(set) var isFiltering = false
    @Published private(set) var overview = AtlasOverviewIndex.empty
    var countryCount: Int { overview.countries.count }

    private var cachedTrips: [Trip] = []
    /// Даты проездов поднимаются ОДИН раз на смену данных: `passes(for:)`
    /// ходит в CoreData на каждое место, а период человек крутит пальцем.
    private var placeSeeds: [AtlasPlaces.Seed] = []
    private var placesReloadTask: Task<Void, Never>?
    /// Окно склейки заказов на перечитывание мест. Не `let` — тест не должен
    /// ждать треть секунды на каждую проверку.
    var placesReloadDebounce: TimeInterval = 0.3
    private var cachedAllTime: (exploration: MapExploration, layer: RevealedLayer)?
    private var filterGeneration = 0

    var isEmpty: Bool { !isLoading && exploration.isEmpty }

    private var loaded = false
    private var stale = false
    private var loadGeneration = 0
    /// Сколько раз пересобиралась вуаль. Читает тест: печати обязаны
    /// перечитываться БЕЗ пересборки тумана — иначе каждая находка стоила бы
    /// полного прохода по библиотеке и вспышки «всё закрыто» на экране.
    private(set) var fogRebuilds = 0
    /// Хранилище находок и каталог загадок — инъекцией, чтобы тест мог дать
    /// свои, не трогая базу телефона и бандл.
    private let discoveryStore: DiscoveryStore
    private let riddleCatalog: RiddleCatalog
    private var discoveryGeneration = 0
    /// Печать, которую попросили показать раньше, чем приехал список печатей.
    private var pendingDiscovery: UUID?
    /// Три уведомления финиша — одна пересборка. Почему это не «три лишних
    /// выборки», а видимая вспышка «всё закрыто», — см. `ReloadCoalescer`.
    private lazy var coalescer = ReloadCoalescer { [weak self] in
        guard let self, self.loaded,
              let tm = self.tripManagerRef, let territory = self.territoryRef else { return }
        await self.reload(tripManager: tm, territory: territory)
    }
    private weak var tripManagerRef: TripManager?
    private weak var territoryRef: TerritoryManager?

    /// Источник поездок для ЧУЖОЙ карты. `nil` у карты владельца — она ходит
    /// в CoreData через `reload(tripManager:territory:)`, как и раньше.
    private let remoteSource: TripSource?
    /// Загрузка чужой карты отвалилась. Отличает «нет публичных поездок» от
    /// «не удалось загрузить» — экран пишет разное.
    @Published private(set) var remoteFailed = false

    /// Чужая карта (0.6.3). Обычный init, а НЕ `.shared`: синглтон переживает
    /// переключение табов и держит состояние карты владельца — чужой аккаунт,
    /// заехавший в него, стёр бы её.
    init(source: TripSource) {
        self.remoteSource = source
        self.discoveryStore = .shared
        self.riddleCatalog = DiscoveryProcessor.shared.riddleCatalog
    }

    /// Строит чужую карту из публичных поездок аккаунта.
    ///
    /// Тот же `MapExploration.build`, что и у своей карты, — форка рендера нет.
    /// Разница ровно в двух местах: поездки приезжают из источника, а туман
    /// считается из тех же координат ЧИСТОЙ функцией и живёт только в памяти.
    /// Ни одна строка отсюда не попадает в `VisitedGeohashEntity`.
    func loadRemote() async {
        guard let remoteSource else { return }
        loadGeneration += 1
        let generation = loadGeneration
        if exploration.isEmpty { isLoading = true }

        await RegionAtlas.shared.loadIfNeeded()

        let result = await remoteSource.load()
        let trips = result.trips
        let atlas = RegionAtlas.shared

        let built = await Task.detached(priority: .userInitiated) {
            let hashes = TerritoryManager.geohashes(
                fromTrips: trips.map { $0.previewCoordinates }, precision: 6)
            // Слой ПЕРВЫМ: открытые километры по регионам считает он, и строка
            // региона обязана печатать то же число, что шапка.
            let layer = Self.remoteLayer(trips: trips, atlas: atlas)
            let exploration = MapExploration.build(
                trips: trips, visitedHashes: hashes, atlas: atlas,
                openedKmByRegion: layer.regionKm)
            return (exploration, layer)
        }.value

        guard generation == loadGeneration else { return }

        // Под тем же гейтом, что и всё остальное: обогнавшая устаревшая
        // загрузка иначе накрыла бы свежие маршруты сообщением об отказе.
        remoteFailed = result.failed
        apply(exploration: built.0, layer: built.1)
        loaded = true
        isLoading = false
    }

    /// Туман чужой (и машинной) карты — на лету, тем же `RevealBuilder`, и
    /// НИ ОДНОЙ строки в базу.
    ///
    /// «Застолблено» здесь копится в памяти вызова: первая поездка через
    /// ячейку владеет геометрией, следующая по той же улице не добавляет
    /// ничего — ровно как на финише своей поездки, только без хранилища.
    /// Своя таблица открытого — единственное хранилище своего тумана, и чужие
    /// ячейки, попавшие туда, закрасили бы его необратимо.
    private nonisolated static func remoteLayer(
        trips: [Trip], atlas: RegionAtlas
    ) -> RevealedLayer {
        AtlasPreviewLayer.build(trips: trips, atlas: atlas)
    }

    /// Каталог загадок берётся у `DiscoveryProcessor.shared` — ЧИТАЕТСЯ, а не
    /// зовётся: ни один матчер отсюда не вызывается, подсказка это загадки из
    /// бандла минус уже решённые. Поэтому файл вписан в allowlist сторожа
    /// `NoLiveSecretPromptsTests` с причиной, а не спрятан за прокладкой с
    /// другим именем: сторож читает текст, и переименование обошло бы его, не
    /// изменив ничего по существу.
    ///
    /// Каталог `nil` — «взять обычный»: значением по умолчанию его не написать,
    /// умолчания считаются на СТОРОНЕ ВЫЗОВА, то есть вне главного актёра.
    init(discoveryStore: DiscoveryStore = .shared,
         riddleCatalog: RiddleCatalog? = nil) {
        // Diagnostic (round 2, 19 сен 2026) — this is the init `MyMapView`'s
        // `@ObservedObject private var vm = MyMapViewModel.shared` triggers
        // on the FIRST visit to the Maps tab, synchronously, before the tab's
        // first frame: `MyMapViewModel.shared` is a plain expression
        // evaluated wherever it's first referenced, and `ContentView.body`'s
        // `switch selectedTab { case .maps: MyMapView() }` references it
        // while building that frame.
        StartupTrace.mark("MyMapViewModel.init begin")
        self.remoteSource = nil
        self.discoveryStore = discoveryStore
        self.riddleCatalog = riddleCatalog ?? DiscoveryProcessor.shared.riddleCatalog
        // Data changes invalidate the map. When the tab is off-screen the
        // reload happens here directly (the view can't); loadIfNeeded also
        // rechecks `stale` on the next appearance as a belt-and-braces.
        // .syncPullCompleted: restore-on-fresh-device / second-device trips
        // land via Cloud-Sync pull, which touches neither territory nor
        // recording — without it the Maps tab stays empty all session.
        // .revealedLayerChanged: финиш поездки и фоновая сборка после
        // обновления пишут открытое мимо этого объекта, прямо в свой контекст
        // CoreData, — без подписки туман не двинулся бы до перезапуска.
        for name: Notification.Name in [.territoryRebuilt, .tripRecordingEnded, .tripDeleted,
                                        .syncPullCompleted, .revealedLayerChanged] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.stale = true
                    // Не `reload()` прямо здесь: на финише этих уведомлений
                    // три, и каждое стоит полной пересборки индекса путей.
                    self.coalescer.schedule()
                }
            }
        }
        // Находки — ОТДЕЛЬНОЙ подпиской, мимо коалесера: печать, легшая на
        // финише, стоит одной выборки строк, а пересборка тумана — прохода по
        // всей библиотеке превью и вспышки «всё закрыто» на экране. Держит
        // `MyMapViewModelSealsTests`.
        NotificationCenter.default.addObserver(
            forName: .discoveriesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.reloadDiscoveries() }
            }
        }
        // Места — тоже отдельной подпиской, мимо коалесера и мимо тумана:
        // заведённое место это одна строка на карте, а пересборка тумана —
        // проход по всей библиотеке превью.
        NotificationCenter.default.addObserver(
            forName: .placesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePlacesReload() }
        }
        // Дом — своей подпиской и без склейки: это одна точка, а не проход по
        // библиотеке, и меняется она ровно тогда, когда человек стоит в листе
        // настройки и смотрит на результат.
        homePin = HomeManager.shared.settings.mapPin
        NotificationCenter.default.addObserver(
            forName: .homeSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.homePin = HomeManager.shared.settings.mapPin
            }
        }
        StartupTrace.mark("MyMapViewModel.init end")
    }

    // MARK: - Места на карте

    /// Заказ на перечитывание — со СКЛЕЙКОЙ, как у подсказок вкладки «Места».
    ///
    /// `PlaceManager.reconcile()` постит `.placesChanged` на КАЖДОЙ поездке с
    /// изменениями, а `reloadPlaces` ходит в CoreData за проездами каждого
    /// места. Без склейки первый запуск после обновления делал бы это сотню
    /// раз подряд с главного актёра — ровно тот класс, что дал Sentry
    /// «App Hanging ≥ 2 с» (см. `PlaceManager.reconcile` в CLAUDE.md).
    /// Держит `PlaceReconcileMainThreadTests`.
    func schedulePlacesReload() {
        // Гейт стоит ЗДЕСЬ, а не только внутри `reloadPlaces`: сверка мест
        // постит `.placesChanged` на каждой из сотен поездок, и четыреста
        // заведённых-и-отменённых задач на главном актёре — это работа,
        // которую видно сторожем, даже если каждая из них ничего не делает.
        guard loaded else { return }
        placesReloadTask?.cancel()
        let debounce = placesReloadDebounce
        placesReloadTask = Task { [weak self] in
            if debounce > 0 {
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
            }
            guard !Task.isCancelled, let self else { return }
            self.reloadPlaces()
        }
    }

    /// Перечитать места и пересобрать булавки. Зовётся на загрузке и по
    /// `.placesChanged`; смена периода сюда не ходит — ей хватает семян.
    func reloadPlaces(manager: PlaceManager = .shared) {
        // «Атлас» ещё не открывали — читать нечего и незачем: проезды каждого
        // места это выборка в CoreData с главного актёра, а сверка мест
        // (`PlaceManager.reconcile`) идёт НА ЗАПУСКЕ, когда человек стоит на
        // ленте. Открытие вкладки зовёт `reload()`, и тот зовёт нас сам —
        // поэтому пропуск здесь ничего не теряет. Держит бюджет главного
        // потока `PlaceReconcileMainThreadTests`.
        guard loaded else { return }
        // Чужая карта своих мест не показывает: места живут только на
        // телефоне (правило 0.6.8), и рисовать на чужом атласе СВОИ значило
        // бы приписать их хозяину профиля.
        guard remoteSource == nil else {
            placeSeeds = []
            placePins = []
            return
        }
        placeSeeds = manager.places.map { place in
            let passes = manager.passes(for: place.id)
            return AtlasPlaces.Seed(
                id: place.id, coordinate: place.coordinate, name: place.name,
                usual: PlaceStats.build(from: passes).medianElapsed,
                passDates: passes.map(\.timestamp))
        }
        rebuildPlacePins()
    }

    /// Только пересчёт «в периоде» — без похода в базу.
    private func rebuildPlacePins() {
        placePins = AtlasPlaces.build(seeds: placeSeeds, period: period)
        // Выбранная булавка могла исчезнуть вместе с местом (удалили на
        // экране места, пока «Атлас» стоял в стеке).
        if let selectedPlaceId, !placePins.contains(where: { $0.id == selectedPlaceId }) {
            self.selectedPlaceId = nil
        }
    }

    /// Место под карточкой на карте.
    var selectedPlace: AtlasPlacePin? {
        selectedPlaceId.flatMap { id in placePins.first { $0.id == id } }
    }

    func loadIfNeeded(tripManager: TripManager, territory: TerritoryManager) async {
        guard !loaded || stale else { return }
        loaded = true
        await reload(tripManager: tripManager, territory: territory)
    }

    func reload(tripManager: TripManager, territory: TerritoryManager) async {
        // Diagnostic (round 2, 19 сен 2026): this is the FIRST async work
        // `MyMapView`'s `.task` kicks off (`loadIfNeeded`) — all off the
        // synchronous first-frame path already (the view shows the empty
        // state / `CarLoadingView` until this finishes), so nothing below
        // is a mark-and-move candidate — it's here to complete the cold vs
        // warm table, not because it blocks paint.
        StartupTrace.mark("MyMapViewModel.reload begin")
        tripManagerRef = tripManager
        territoryRef = territory
        stale = false
        loadGeneration += 1
        let generation = loadGeneration
        // Loader only when there is nothing on screen yet. Background
        // refreshes of an already-populated map must not flash over the
        // still-rendered content.
        if exploration.isEmpty { isLoading = true }

        await RegionAtlas.shared.loadIfNeeded()
        StartupTrace.mark("MyMapViewModel.reload RegionAtlas.loadIfNeeded done")

        // Main-actor: CoreData fetch. Everything after it is pure value work.
        let trips = tripManager.fetchTripsForMap()
        StartupTrace.mark("MyMapViewModel.reload fetchTripsForMap done")
        let hashes = territory.visitedGeohashes
        let atlas = RegionAtlas.shared
        // Открытое читается ГОТОВЫМ — своим фоновым контекстом, не главным
        // актёром. Пересчитывать туман по всем поездкам на каждое открытие
        // вкладки стоило бы 0.5–2 с; чтение тайлов — 50–150 мс.
        let tiles = await RevealedLayerStore.shared.tiles()
        StartupTrace.mark("MyMapViewModel.reload tiles() done")

        let built = await Task.detached(priority: .userInitiated) {
            // Оверлеи собираются здесь же: превращение сети в `MKPolyline` —
            // это тысячи аллокаций, и на главном актёре они задерживали первый
            // кадр карты. И слой строится ПЕРВЫМ: открытые километры по
            // регионам приходят из него, а не из второго счёта рядом.
            let layer = RevealedLayer.build(tiles: tiles, atlas: atlas)
            let exploration = MapExploration.build(
                trips: trips, visitedHashes: hashes, atlas: atlas,
                openedKmByRegion: layer.regionKm)
            return (exploration, layer)
        }.value
        StartupTrace.mark("MyMapViewModel.reload build done")

        // A newer reload superseded this one while the build was detached.
        guard generation == loadGeneration else { return }

        cachedTrips = trips
        cachedAllTime = (built.0, built.1)
        _ = await applyCurrentPeriod()
        reloadPlaces()
        StartupTrace.mark("MyMapViewModel.reload apply done")
        await reloadDiscoveries()
        StartupTrace.mark("MyMapViewModel.reload end")
    }

    // MARK: - Atlas controls

    func setPeriod(_ newPeriod: AtlasPeriod) async {
        guard newPeriod != period else { return }
        period = newPeriod
        select(nil)
        rebuildPlacePins()
        let applied = await applyCurrentPeriod()
        // An explicit period change should leave its roads on screen, even
        // when they are far from the neighbourhood the user was inspecting.
        if applied, period == newPeriod, !isFiltering { fitAll() }
    }

    /// Cache the all-time snapshot once per data change. Picking a period
    /// rebuilds only value data off the main actor; returning to all time is
    /// immediate and restores the persistent layer exactly.
    private func applyCurrentPeriod() async -> Bool {
        filterGeneration += 1
        let generation = filterGeneration
        guard let cachedAllTime else { return false }
        if period == .allTime {
            apply(exploration: cachedAllTime.exploration, layer: cachedAllTime.layer)
            isFiltering = false
            isLoading = false
            return true
        }
        isFiltering = true
        let selectedPeriod = period
        let allTrips = cachedTrips
        let now = Date()
        let calendar = Calendar.current
        let atlas = RegionAtlas.shared
        let built = await Task.detached(priority: .userInitiated) {
            let trips = allTrips.filter {
                $0.previewPolyline?.isEmpty == false
                    && selectedPeriod.contains($0.startDate, now: now, calendar: calendar)
            }
            let layer = AtlasPreviewLayer.build(trips: trips, atlas: atlas)
            let hashes = TerritoryManager.geohashes(
                fromTrips: trips.map(\.previewCoordinates), precision: 6)
            let exploration = MapExploration.build(
                trips: trips, visitedHashes: hashes, atlas: atlas,
                openedKmByRegion: layer.regionKm)
            return (exploration, layer)
        }.value
        guard generation == filterGeneration else { return false }
        apply(exploration: built.0, layer: built.1)
        isFiltering = false
        isLoading = false
        return true
    }

    private func reloadSelectedRegionTrips() {
        guard case .region(let id)? = selection, let region = exploration.region(id: id) else {
            if !selectedRegionTrips.isEmpty { selectedRegionTrips = [] }
            return
        }
        selectedRegionTrips = region.tripIds
            .compactMap { exploration.trip(id: $0) }
            .sorted { $0.startDate > $1.startDate }
    }

    func fitAll() {
        guard let bounds = GeoBounds(covering: exploration.trips.flatMap(\.route)) else { return }
        cameraCommand = .fit(bounds, padding: .overview)
    }

    func locateUser() {
        cameraCommand = .userLocation
    }

    // MARK: - Находки

    /// Печати и подсказки — из базы и каталога, без единого трека.
    ///
    /// Разбор поездок сюда не заходит и не может: находки считает финиш
    /// (`DiscoveryProcessor`), а «Атлас» читает уже готовое — как туман.
    ///
    /// Поколение, а не флаг: `.discoveriesChanged` приходит пачкой (финиш
    /// поездки находит секрет, загадку и веху), и обогнанная выборка не имеет
    /// права накрыть свежую.
    /// - Parameter layer: открытый слой, по которому считается плотность и
    ///   близость. По умолчанию — свой, только что собранный `reload`;
    ///   параметром он ради теста подсказок, которому иначе пришлось бы поднять
    ///   CoreData, атлас и тайлы тумана ради двух центроидов.
    func reloadDiscoveries(layer: RevealedLayer? = nil) async {
        // Чужая карта своих печатей не показывает и чужих не знает: находки
        // живут только на телефоне владельца.
        guard remoteSource == nil else { return }
        // Владелец 22 сен 2026 отложил находки до после 1.0.0
        // (`DiscoveriesAvailability`): выключенный флаг — пустые печати и
        // подсказки, журнал без них, а отложенная печать («покажи мне вот
        // эту») забывается — ждать ей больше нечего. Стор при этом не
        // трогаем: пул продолжает класть в него строки.
        guard DiscoveriesAvailability.isActive else {
            seals = []
            riddleHints = []
            rebuildJournal()
            pendingDiscovery = nil
            return
        }
        discoveryGeneration += 1
        let generation = discoveryGeneration
        let found = await discoveryStore.all()
        guard generation == discoveryGeneration else { return }

        let solved = Set(found.filter { $0.kind == .riddle }.map(\.key))
        let layer = layer ?? revealed
        let centroids = Array(layer.regionCentroids.values)
        let catalog = riddleCatalog
        let hints = RiddleHint.plan(
            riddles: catalog.all(), solvedRiddleIds: solved,
            centroids: centroids, layer: layer)

        seals = found
        riddleHints = hints
        rebuildJournal()
        // Печать, которую попросили показать, пока её ещё не было в списке.
        // Ожидание живёт РОВНО ОДНУ выборку: не нашлась — забыли. Иначе id,
        // которого в базе нет вовсе (удалили находку, гонка пула, чужая
        // ссылка), лежал бы вечно и однажды увёл бы камеру посреди чужого
        // жеста — на первой же выборке, где он случайно совпал.
        if let awaited = pendingDiscovery {
            pendingDiscovery = nil
            if found.contains(where: { $0.id == awaited }) { focusDiscovery(awaited) }
        }
        // Печать, которой больше нет (стёрли аккаунт, пересчитали базу), не
        // имеет права оставаться выбранной — карточка показывала бы призрак.
        if let current = selection, resolve(current) == nil { selection = nil }
    }

    /// Единственное место, где меняются модель экрана и оверлеи — вместе.
    private func apply(exploration: MapExploration, layer: RevealedLayer) {
        self.exploration = exploration
        overview = AtlasOverviewIndex(
            exploration: exploration, catalogRegions: RegionAtlas.shared.regions,
            catalogCities: RegionAtlas.shared.citiesByRegion.values.flatMap { $0 },
            historical: cachedAllTime?.exploration)
        revealed = layer
        fogRebuilds += 1
        // Вуаль есть ВСЕГДА, даже над пустым слоем: угол без неё читался бы
        // как открытый, а «мир тёмный, пока ты не поехал» — это и есть весь
        // замысел.
        fogVeil = FogVeilOverlay(layer: layer)
        routeVein = layer.isEmpty ? nil : RouteVeinOverlay(layer: layer)
        // Drop a selection whose subject no longer exists (trip deleted on
        // another device, region emptied by a rebuild).
        if let current = selection, resolve(current) == nil { selection = nil }
        refreshSelectedRoute()
        reloadSelectedRegionTrips()
        rebuildJournal()
    }

    /// Журнал пересобирается ровно там, где меняется хоть одна его половина:
    /// регионы и километры — в `apply`, печати и круги — в
    /// `reloadDiscoveries`. Обе двери, а не одна: чужая карта до находок не
    /// доходит вовсе (`reloadDiscoveries` выходит на первой строке), а
    /// `.discoveriesChanged` приходит мимо `apply`.
    private func rebuildJournal() {
        journal = JournalBuilder.build(
            exploration: exploration, revealed: revealed,
            seals: seals, hints: riddleHints)
    }

    // MARK: - Selected route

    /// Держит `selectedRoute` в шаге с выбором.
    ///
    /// Синхронно и без кэша: жилка рисуется по превью, которое уже лежит в
    /// `exploration`. Прежняя версия ходила в CoreData за точками поездки,
    /// считала им скорости и держала восемь построенных линий в памяти —
    /// всё это было ценой градиента скорости, которого на Атласе больше нет.
    private func refreshSelectedRoute() {
        guard case .trip(let id) = selection, let pin = exploration.trip(id: id) else {
            selectedRoute = nil
            return
        }
        selectedRoute = RouteVeinOverlay(route: pin.route)
    }

    // MARK: - Selection

    /// Тап по фону карты: открытый регион — его карточка, всё остальное —
    /// назад к сводке.
    ///
    /// «Закрытый регион» карточки больше не открывает: в 0.7.0 его на карте
    /// нет вовсе, и предлагать разбор того, чего человек не видит, значило бы
    /// вернуть игровую карту территорий, из-за которой карта и читалась как
    /// Risk, а не как туман.
    func selectRegion(at coordinate: CLLocationCoordinate2D, zoom: Bool = true) {
        guard let region = RegionAtlas.shared.region(containing: coordinate),
              exploration.region(id: region.id) != nil else {
            select(nil)
            return
        }
        select(.region(region.id), zoom: zoom)
    }

    /// Tap on a road. One trip goes straight to its card; several open the
    /// list, without moving the camera — you are already looking at the road
    /// you asked about.
    func selectRoad(_ tripIds: [UUID]) {
        let byDate = tripIds
            .compactMap { exploration.trip(id: $0) }
            .sorted { $0.startDate > $1.startDate }
            .map(\.id)
        guard let first = byDate.first else { return }
        // Never move the camera on a road tap, not even for a single trip:
        // you pointed at a street, and fitting a 250 km drive to the screen
        // throws you out of the neighbourhood you were reading.
        select(byDate.count == 1 ? .trip(first) : .road(byDate), zoom: false)
    }

    func select(_ new: Selection?, zoom: Bool = true) {
        guard new != selection else { return }
        selection = new
        refreshSelectedRoute()
        reloadSelectedRegionTrips()
        guard zoom, let new else { return }
        switch new {
        case .region(let id):
            if let region = RegionAtlas.shared.region(id: id) {
                cameraCommand = .fit(region.bounds, padding: .region)
            }
        // A road pick never moves the camera — you are already looking at the
        // road you asked about, and `selectRoad` passes zoom: false anyway.
        case .road:
            break
        // Печать — тем более: палец уже стоит на ней, и полёт камеры увёз бы
        // человека с того места, про которое он спросил.
        case .discovery:
            break
        case .trip(let id):
            if let pin = exploration.trip(id: id), let bounds = GeoBounds(covering: pin.route) {
                cameraCommand = .fit(bounds, padding: .trip)
            }
        }
    }

    // MARK: - Переход к находке

    /// Показать печать, названную снаружи (блок «Открыто» на экране итогов,
    /// вторая фаза `.openDiscovery → .navigateToDiscovery`).
    ///
    /// Камера здесь ДВИГАЕТСЯ — в отличие от тапа по самой печати: человек
    /// пришёл с другого экрана и не знает, в какой угол мира смотрит карта.
    /// Масштаб городской (`focusSpanMetres`), а не «весь регион»: печать
    /// стоит в конкретном месте, и показывать её точкой посреди края значит
    /// не показывать вовсе.
    ///
    /// Печати может ещё не быть: вкладка только смонтировалась, и выборка идёт.
    /// Тогда id запоминается и применяется, как только список приедет, —
    /// молчать было бы хуже всего, переход просто не случился бы.
    func focusDiscovery(_ id: UUID) {
        guard let seal = seals.first(where: { $0.id == id }) else {
            pendingDiscovery = id
            return
        }
        pendingDiscovery = nil
        select(.discovery(id), zoom: false)
        cameraCommand = .fit(
            GeoBounds(around: seal.coordinate, metres: Self.focusSpanMetres), padding: .trip)
    }

    /// Ширина кадра вокруг печати — двенадцать километров: город целиком и
    /// дорога, которой к печати приехали.
    static let focusSpanMetres: Double = 12_000

    /// Selection → the thing it points at, or nil if it went away.
    private func resolve(_ selection: Selection) -> Any? {
        switch selection {
        case .region(let id):       return exploration.region(id: id)
        case .trip(let id):         return exploration.trip(id: id)
        case .road(let ids):        return selectedRoadTrips(ids).isEmpty ? nil : ids
        case .discovery(let id):    return seals.first { $0.id == id }
        }
    }

    /// The trips behind a road selection, minus any that have since gone.
    func selectedRoadTrips(_ ids: [UUID]) -> [MapTripPin] {
        ids.compactMap { exploration.trip(id: $0) }
    }

    var selectedRoad: [MapTripPin]? {
        guard case .road(let ids) = selection else { return nil }
        return selectedRoadTrips(ids)
    }

    var selectedRegion: MapRegionStat? {
        guard case .region(let id) = selection else { return nil }
        return exploration.region(id: id)
    }

    var selectedTrip: MapTripPin? {
        guard case .trip(let id) = selection else { return nil }
        return exploration.trip(id: id)
    }

    var selectedDiscovery: Discovery? {
        guard case .discovery(let id) = selection else { return nil }
        return seals.first { $0.id == id }
    }
}

// MARK: - Camera

/// One-shot camera instructions from the VM to the map view.
enum MapCameraCommand: Equatable {
    case fit(GeoBounds, padding: Padding)
    case userLocation

    enum Padding {
        /// Collapsed atlas plus navigation. Also used for search targets
        /// which frame the map without opening a detail card.
        case overview
        /// The region card and its navigation clearance occupy 460 points.
        case region
        /// The trip card includes the navigation clearance below its body.
        case trip

        /// Сколько хрома закрывает карту, считая от КРАЁВ экрана.
        var chrome: UIEdgeInsets {
            switch self {
            case .overview: return UIEdgeInsets(top: 110, left: 40, bottom: 300, right: 40)
            case .region: return UIEdgeInsets(top: 110, left: 32, bottom: 480, right: 32)
            case .trip:   return UIEdgeInsets(top: 110, left: 44, bottom: 310, right: 44)
            }
        }

        /// Минимум, который обязан остаться карте после всех полей. Ниже
        /// этого просить бессмысленно: MapKit на отрицательном остатке
        /// отвечает кадром во весь мир.
        static let minimumViewport: CGFloat = 120

        /// Отступы для `setVisibleMapRect`, посчитанные от ФАКТИЧЕСКОЙ
        /// безопасной зоны карты.
        ///
        /// MapKit кадрирует камеру по СУММЕ безопасной зоны (полей разметки)
        /// и переданного `edgePadding` — это записано в CLAUDE.md с 0.7.0 и
        /// ровно на этом здесь всё и ломалось. Карта «Атласа» отдаёт листу
        /// ~290 pt снизу через `additionalSafeAreaInsets`, а `.region` просил
        /// ещё 480: по вертикали на экране 874 pt оставалось −68, и MapKit
        /// отвечал кадром в пять раз шире запрошенного — «нажал регион, а
        /// меня унесло куда-то вникуда» (владелец на устройстве 26 сен).
        ///
        /// Поэтому просим ДОБАВКУ к тому, что зона уже дала, и обрезаем её,
        /// если карте не остаётся `minimumViewport`. Чистая функция — потому
        /// что проверить это можно только числом, а не открытым экраном.
        static func insets(chrome: UIEdgeInsets, safeArea: UIEdgeInsets,
                           size: CGSize) -> UIEdgeInsets {
            func extra(_ want: CGFloat, _ have: CGFloat) -> CGFloat { max(0, want - have) }
            var top = extra(chrome.top, safeArea.top)
            var bottom = extra(chrome.bottom, safeArea.bottom)
            var left = extra(chrome.left, safeArea.left)
            var right = extra(chrome.right, safeArea.right)

            // Остаток считается от того же, от чего его считает MapKit:
            // размер минус безопасная зона минус наша добавка.
            func fit(_ a: inout CGFloat, _ b: inout CGFloat,
                     total: CGFloat, safe: CGFloat) {
                let free = total - safe
                guard free > 0 else { a = 0; b = 0; return }
                let room = free - minimumViewport
                guard room < a + b else { return }
                guard room > 0 else { a = 0; b = 0; return }
                let scale = room / (a + b)
                a *= scale
                b *= scale
            }
            fit(&top, &bottom, total: size.height, safe: safeArea.top + safeArea.bottom)
            fit(&left, &right, total: size.width, safe: safeArea.left + safeArea.right)
            return UIEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        }

        func insets(safeArea: UIEdgeInsets, size: CGSize) -> UIEdgeInsets {
            Self.insets(chrome: chrome, safeArea: safeArea, size: size)
        }
    }
}

extension GeoBounds: Equatable {
    /// Квадрат заданной ширины вокруг точки.
    ///
    /// Чистой функцией и здесь же, рядом с `covering`: вторая арифметика
    /// «градусы из метров» в проекте однажды разъехалась бы с первой. Долгота
    /// делится на косинус широты — иначе на шестидесятой параллели кадр
    /// выходит вдвое уже, чем просили.
    init(around centre: CLLocationCoordinate2D, metres: Double) {
        let metresPerDegree = 111_320.0
        let half = metres / 2
        let dLat = half / metresPerDegree
        let dLon = half / (metresPerDegree * max(0.01, cos(centre.latitude * .pi / 180)))
        self = GeoBounds(
            minLat: centre.latitude - dLat, maxLat: centre.latitude + dLat,
            minLon: centre.longitude - dLon, maxLon: centre.longitude + dLon)
    }

    init?(covering coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else { return nil }
        var box = GeoBounds(minLat: 90, maxLat: -90, minLon: 180, maxLon: -180)
        for c in coordinates {
            box.minLat = min(box.minLat, c.latitude)
            box.maxLat = max(box.maxLat, c.latitude)
            box.minLon = min(box.minLon, c.longitude)
            box.maxLon = max(box.maxLon, c.longitude)
        }
        self = box
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    var mapRect: MKMapRect {
        let a = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let b = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        let rect = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(a.x - b.x), height: abs(a.y - b.y))
        // A trip that never moved — or one point that survived filtering —
        // gives a zero-size rect, and `setVisibleMapRect` answers that by
        // zooming to the tightest level the map has. Give it a block to look
        // at instead.
        let floor = 300 * MKMapPointsPerMeterAtLatitude(center.latitude)
        guard rect.width < floor || rect.height < floor else { return rect }
        return MKMapRect(
            x: rect.midX - max(rect.width, floor) / 2,
            y: rect.midY - max(rect.height, floor) / 2,
            width: max(rect.width, floor),
            height: max(rect.height, floor)
        )
    }

    /// Great-circle distance from a coordinate to the nearest point of the box
    /// (zero when inside).
    func nearestEdgeDistance(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
        let lat = min(max(coordinate.latitude, minLat), maxLat)
        let lon = min(max(coordinate.longitude, minLon), maxLon)
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    public static func == (lhs: GeoBounds, rhs: GeoBounds) -> Bool {
        lhs.minLat == rhs.minLat && lhs.maxLat == rhs.maxLat
            && lhs.minLon == rhs.minLon && lhs.maxLon == rhs.maxLon
    }
}
