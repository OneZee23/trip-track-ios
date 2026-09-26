import Foundation
import Combine
import CoreLocation

/// Экран места: всё считается здесь на загрузке и по `.placesChanged`.
/// Нитки — превью поездок с проездами (одна лёгкая выборка `tripPreviews`,
/// не `fetchTripDetail` на каждый проезд); подпись направления — имя места
/// из кэша геокодера по КОНЦУ самой свежей поездки этого направления
/// («к морю», «домой»); нет в кэше — стрелки хватит.
@MainActor
final class PlaceDetailViewModel: ObservableObject {
    @Published private(set) var place: Place?
    @Published private(set) var stats = PlaceStats.build(from: [])
    @Published private(set) var passes: [PlacePass] = []
    @Published private(set) var routes: [[CLLocationCoordinate2D]] = []
    @Published private(set) var directionLabels: [UUID: String] = [:]
    /// «Краснодар → Горячий Ключ» на строку проезда, по его поездке.
    /// Считается здесь, а не в `body`: концы берутся у превью, а имена — из
    /// кэша геокодера, то есть из базы.
    @Published private(set) var routeNames: [UUID: String] = [:]
    /// Имя, которое даёт этому месту геокодер («Горячий Ключ»). Хранится
    /// СЫРЫМ, без сравнения с именем места: лист переименования показывает
    /// его и тогда, когда они совпали, — туда за ним и приходят, чтобы
    /// вернуть название по адресу.
    @Published private(set) var geocodedName: String?
    /// Строка под именем на экране. Пусто, когда имя места И ЕСТЬ этот
    /// город: повторять его второй строкой нечего.
    var address: String? {
        guard let geocodedName else { return nil }
        return geocodedName.caseInsensitiveCompare(place?.name ?? "") == .orderedSame ? nil : geocodedName
    }
    /// Плитки «Последних проездов»: по одной на ДЕНЬ.
    @Published private(set) var tiles: [PlaceScreen.DateTile] = []
    /// «Все 23 проезда» нажали — список больше не подрезается.
    @Published var showsAllPasses = false

    let placeId: UUID
    private let manager: PlaceManager
    private let repository: TripRepository
    private let localityLookup: (CLLocationCoordinate2D) -> String?
    private var cancellables = Set<AnyCancellable>()

    /// Ниток на карте — не больше двадцати самых свежих: сотня полилиний
    /// закрасила бы карту целиком.
    static let maxRoutes = 20

    init(placeId: UUID,
         manager: PlaceManager = .shared,
         repository: TripRepository = CoreDataTripRepository(),
         localityLookup: ((CLLocationCoordinate2D) -> String?)? = nil) {
        self.placeId = placeId
        self.manager = manager
        self.repository = repository
        self.localityLookup = localityLookup ?? { [repository] in repository.cachedLocality(for: $0) }
        NotificationCenter.default.publisher(for: .placesChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
            .store(in: &cancellables)
    }

    func load() {
        place = manager.places.first { $0.id == placeId }
        let all = manager.passes(for: placeId)
        passes = all.sorted { $0.timestamp > $1.timestamp }
        stats = PlaceStats.build(from: all)
        let recentTripIds = Array(passes.map(\.tripId).uniqued().prefix(Self.maxRoutes))
        // `uniqueKeysWithValues` падает на дубле `TripEntity.id` — модель не
        // объявляет его уникальность, а дубли это известный класс синк-багов.
        let previews = Dictionary(repository.tripPreviews(needingPlaceMatch: false).map { ($0.id, $0) },
                                   uniquingKeysWith: { a, _ in a })
        routes = recentTripIds.compactMap { previews[$0]?.previewCoordinates }.filter { $0.count > 1 }
        var labels: [UUID: String] = [:]
        for direction in stats.directions {
            if let end = previews[direction.latestTripId]?.previewCoordinates.last, let name = localityLookup(end) {
                labels[direction.latestTripId] = name
            }
        }
        directionLabels = labels
        tiles = PlaceScreen.tiles(from: all)
        // Из того же кэша геокодера, что и всё остальное; своего запроса
        // экран не делает (правило 0.8.0: пять сетевых кругов на открытие).
        geocodedName = place.flatMap { localityLookup($0.coordinate) }.flatMap { $0.isEmpty ? nil : $0 }
        routeNames = composeRouteNames(previews: previews)
    }

    /// Подписи «откуда → куда» на все проезды разом.
    ///
    /// Кэш геокодера спрашивается по ЯЧЕЙКЕ (geohash-5), а не по координате:
    /// у двадцати трёх проездов из одного города концов пара, а не сорок
    /// шесть, и без этого дедупа список стоил бы по выборке на строку.
    private func composeRouteNames(previews: [UUID: TripPreviewRef]) -> [UUID: String] {
        var cache: [String: String?] = [:]
        func name(_ coordinate: CLLocationCoordinate2D) -> String? {
            let key = TripManager.geocodeCacheKey(for: coordinate)
            if let hit = cache[key] { return hit }
            let value = localityLookup(coordinate)
            cache[key] = value
            return value
        }
        var result: [UUID: String] = [:]
        for tripId in Set(passes.map(\.tripId)) {
            guard let ends = PlaceScreen.endpoints(of: previews[tripId]?.previewCoordinates ?? []) else { continue }
            if let line = PlaceScreen.route(from: name(ends.start), to: name(ends.end)) {
                result[tripId] = line
            }
        }
        return result
    }

    func rename(_ name: String?) { manager.rename(placeId: placeId, to: name) }

    func delete() { manager.delete(placeId: placeId); place = nil }

    /// Открыть поездку проезда: на своей отметке этого места — с фокусом на
    /// ней; история без отметки (поездка мимо) — сверху.
    func focus(forPassOf tripId: UUID) -> TripFocus {
        if let cp = repository.fetchTripDetail(id: tripId)?.checkpoints.first(where: { $0.placeId == placeId }) {
            return .checkpoint(cp.id)
        }
        return .top
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
