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
    /// Set through `select` / `selectRoad` only — the drawn route is kept in
    /// step from there, and a direct write would leave the two disagreeing.
    @Published private(set) var selection: Selection?
    /// One-shot camera command consumed by the map (`nil` once applied).
    @Published var cameraCommand: MapCameraCommand?

    var isEmpty: Bool { !isLoading && exploration.isEmpty }

    private var loaded = false
    private var stale = false
    private var loadGeneration = 0
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
            let exploration = MapExploration.build(
                trips: trips, visitedHashes: hashes, atlas: atlas)
            return (exploration, Self.remoteLayer(trips: trips, atlas: atlas))
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
        var claimed: [String: Set<RevealGrid.Cell>] = [:]
        var runs: [[CLLocationCoordinate2D]] = []
        for trip in trips.sorted(by: { $0.startDate < $1.startDate }) {
            let coords = trip.previewCoordinates
            guard coords.count > 1 else { continue }
            let patches = RevealBuilder.patches(for: coords) { claimed[$0] ?? [] }
            for (key, patch) in patches {
                claimed[key, default: []].formUnion(patch.cells)
                runs.append(contentsOf: patch.runs)
            }
        }
        return RevealedLayer.build(
            runs: runs, cellCount: claimed.values.reduce(0) { $0 + $1.count }, atlas: atlas)
    }

    init() {
        self.remoteSource = nil
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
                Task { @MainActor in
                    guard let self else { return }
                    self.stale = true
                    if self.loaded, let tm = self.tripManagerRef, let t = self.territoryRef {
                        await self.reload(tripManager: tm, territory: t)
                    }
                }
            }
        }
    }

    func loadIfNeeded(tripManager: TripManager, territory: TerritoryManager) async {
        guard !loaded || stale else { return }
        loaded = true
        await reload(tripManager: tripManager, territory: territory)
    }

    func reload(tripManager: TripManager, territory: TerritoryManager) async {
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

        // Main-actor: CoreData fetch. Everything after it is pure value work.
        let trips = tripManager.fetchTripsForMap()
        let hashes = territory.visitedGeohashes
        let atlas = RegionAtlas.shared
        // Открытое читается ГОТОВЫМ — своим фоновым контекстом, не главным
        // актёром. Пересчитывать туман по всем поездкам на каждое открытие
        // вкладки стоило бы 0.5–2 с; чтение тайлов — 50–150 мс.
        let tiles = await RevealedLayerStore.shared.tiles()

        let built = await Task.detached(priority: .userInitiated) {
            let exploration = MapExploration.build(trips: trips, visitedHashes: hashes, atlas: atlas)
            // Оверлеи собираются здесь же: превращение сети в `MKPolyline` —
            // это тысячи аллокаций, и на главном актёре они задерживали первый
            // кадр карты.
            return (exploration, RevealedLayer.build(tiles: tiles, atlas: atlas))
        }.value

        // A newer reload superseded this one while the build was detached.
        guard generation == loadGeneration else { return }

        apply(exploration: built.0, layer: built.1)
        isLoading = false
    }

    /// Единственное место, где меняются модель экрана и оверлеи — вместе.
    private func apply(exploration: MapExploration, layer: RevealedLayer) {
        self.exploration = exploration
        revealed = layer
        // Вуаль есть ВСЕГДА, даже над пустым слоем: угол без неё читался бы
        // как открытый, а «мир тёмный, пока ты не поехал» — это и есть весь
        // замысел.
        fogVeil = FogVeilOverlay(layer: layer)
        routeVein = layer.isEmpty ? nil : RouteVeinOverlay(layer: layer)
        // Drop a selection whose subject no longer exists (trip deleted on
        // another device, region emptied by a rebuild).
        if let current = selection, resolve(current) == nil { selection = nil }
        refreshSelectedRoute()
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
        case .trip(let id):
            if let pin = exploration.trip(id: id), let bounds = GeoBounds(covering: pin.route) {
                cameraCommand = .fit(bounds, padding: .trip)
            }
        }
    }

    /// Selection → the thing it points at, or nil if it went away.
    private func resolve(_ selection: Selection) -> Any? {
        switch selection {
        case .region(let id):       return exploration.region(id: id)
        case .trip(let id):         return exploration.trip(id: id)
        case .road(let ids):        return selectedRoadTrips(ids).isEmpty ? nil : ids
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
}

// MARK: - Camera

/// One-shot camera instructions from the VM to the map view.
enum MapCameraCommand: Equatable {
    case fit(GeoBounds, padding: Padding)

    enum Padding {
        /// Region card is 214 pt tall — leave the region visible above it.
        case region
        /// Trip card is 176 pt.
        case trip

        var insets: UIEdgeInsets {
            switch self {
            case .region: return UIEdgeInsets(top: 130, left: 32, bottom: 250, right: 32)
            case .trip:   return UIEdgeInsets(top: 130, left: 44, bottom: 220, right: 44)
            }
        }
    }
}

extension GeoBounds: Equatable {
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
