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
        let previews = Dictionary(uniqueKeysWithValues: repository.tripPreviews(needingPlaceMatch: false).map { ($0.id, $0) })
        routes = recentTripIds.compactMap { previews[$0]?.previewCoordinates }.filter { $0.count > 1 }
        var labels: [UUID: String] = [:]
        for direction in stats.directions {
            if let end = previews[direction.latestTripId]?.previewCoordinates.last, let name = localityLookup(end) {
                labels[direction.latestTripId] = name
            }
        }
        directionLabels = labels
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
