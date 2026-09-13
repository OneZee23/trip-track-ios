import Foundation
import Combine
import CoreLocation

/// Места (0.6.8): отметка рождает место, поездка оставляет проезды.
///
/// Пять входов, и все ведут сюда:
///  • новая отметка → место (или уже известное) + история по библиотеке;
///  • финиш поездки (после `PostTripTrackProcessor`, на окончательном треке) →
///    проезды мимо всех мест;
///  • пул синка → сверка: отметки без места, поездки без сверки;
///  • удаление поездки → её проезды забываются;
///  • запуск → та же сверка, что после пула (`placesMatchedAt` помнит,
///    что уже сделано, поэтому обычный запуск не стоит ничего).
///
/// Всё считается на главном потоке через `viewContext` — как
/// `TerritoryManager.backfillIfNeeded` и `PostTripTrackProcessor`; между
/// поездками — `Task.yield()`, чтобы первая сверка большой библиотеки не
/// замораживала экран. Точки поездки поднимаются ТОЛЬКО для кандидатов
/// предфильтра: у большинства поездок мест рядом нет.
@MainActor
final class PlaceManager: ObservableObject {
    static let shared = PlaceManager()

    @Published private(set) var places: [Place] = []

    private let repository: TripRepository
    private let store: PlaceStore
    private var cancellables = Set<AnyCancellable>()
    /// Досчёт истории после новой отметки идёт отдельной задачей; тесты и
    /// вызывающие, которым нужен результат, ждут её через `settle()`.
    private var backfillTask: Task<Void, Never>?

    init(repository: TripRepository = CoreDataTripRepository(),
         store: PlaceStore = CoreDataPlaceStore(context: PersistenceController.shared.container.viewContext)) {
        self.repository = repository
        self.store = store
        reload()
        // Поездка и отметки со второго телефона приезжают пулом прямо в
        // CoreData — мимо всех, кто зовёт менеджер руками.
        NotificationCenter.default.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.reconcile() }
            }
            .store(in: &cancellables)
    }

    func reload() { places = store.fetchPlaces() }

    func passes(for placeId: UUID) -> [PlacePass] { store.passes(placeId: placeId) }

    func stats(for placeId: UUID) -> PlaceStats { PlaceStats.build(from: store.passes(placeId: placeId)) }

    /// Дождаться досчёта истории, начатого `registerCheckpoint`.
    func settle() async { await backfillTask?.value }

    // MARK: - Отметка → место

    /// Каждая отметка с координатой — место; две в одной ячейке — одно.
    /// Новое место сразу получает историю по всей библиотеке; у известного
    /// история уже есть, а проезд ЭТОЙ поездки допишет финиш (или сверка,
    /// если поездка уже завершена).
    func registerCheckpoint(_ checkpoint: TripCheckpoint, tripId: UUID) {
        let cell = Place.cell(latitude: checkpoint.latitude, longitude: checkpoint.longitude)
        let (place, isNew) = store.upsertPlace(cell: cell, coordinate: checkpoint.coordinate, name: checkpoint.name)
        repository.setPlaceId(forCheckpoint: checkpoint.id, placeId: place.id)
        store.recomputeCentroid(placeId: place.id, from: repository.checkpointCoordinates(placeId: place.id))
        reload()
        if isNew {
            backfillTask = Task { [weak self] in
                await self?.matchAllTrips(against: place)
            }
        } else if repository.tripPreviews(needingPlaceMatch: false).contains(where: { $0.id == tripId }) {
            backfillTask = Task { [weak self] in
                await self?.process(tripId: tripId)
            }
        }
    }

    /// Геокодер назвал отметку — безымянное место берёт то же имя.
    func adoptName(_ name: String, forCheckpoint id: UUID, tripId: UUID) {
        guard let placeId = repository.fetchTripDetail(id: tripId)?
                .checkpoints.first(where: { $0.id == id })?.placeId else { return }
        store.adoptName(name, forPlace: placeId)
        reload()
    }

    // MARK: - Поездка → проезды

    /// Проезды одной поездки мимо всех мест. Зовётся после финиша (на
    /// окончательном треке) и из сверки. Поездка без мест рядом всё равно
    /// помечается сверенной — иначе запуск перебирал бы её вечно.
    func process(tripId: UUID) async {
        defer { repository.markPlacesMatched(tripId: tripId) }
        let candidates = candidatePlaces(for: repository.tripPreviews(needingPlaceMatch: false)
            .first { $0.id == tripId })
        guard !candidates.isEmpty,
              let trip = repository.fetchTripDetail(id: tripId), trip.trackPoints.count > 1 else { return }
        var changed = false
        for place in candidates {
            let passes = PlaceMatcher.passes(through: place, tripId: trip.id, points: trip.trackPoints, startDate: trip.startDate)
            if !passes.isEmpty || !store.passes(tripId: tripId).filter({ $0.placeId == place.id }).isEmpty {
                store.replacePasses(placeId: place.id, tripId: trip.id, with: passes)
                changed = true
            }
        }
        if changed { NotificationCenter.default.post(name: .placesChanged, object: nil) }
    }

    /// История нового места по всей библиотеке: предфильтр по превью,
    /// точки — только у кандидатов.
    func matchAllTrips(against place: Place) async {
        var changed = false
        for ref in repository.tripPreviews(needingPlaceMatch: false) {
            guard PlaceMatcher.isCandidate(place: place, tripCells: PlaceMatcher.cells(of: ref.previewCoordinates)),
                  let trip = repository.fetchTripDetail(id: ref.id), trip.trackPoints.count > 1 else { continue }
            let passes = PlaceMatcher.passes(through: place, tripId: trip.id, points: trip.trackPoints, startDate: trip.startDate)
            if !passes.isEmpty {
                store.replacePasses(placeId: place.id, tripId: trip.id, with: passes)
                changed = true
            }
            await Task.yield()
        }
        if changed { NotificationCenter.default.post(name: .placesChanged, object: nil) }
    }

    /// Сверка — после пула и при запуске. Идемпотентна: трогает только
    /// отметки без места и поездки без `placesMatchedAt`.
    func reconcile() async {
        for (checkpoint, tripId) in repository.checkpointsWithoutPlace() {
            registerCheckpoint(checkpoint, tripId: tripId)
            await settle()
        }
        for ref in repository.tripPreviews(needingPlaceMatch: true) {
            await process(tripId: ref.id)
            await Task.yield()
        }
        reload()
    }

    // MARK: - Удаление

    func forget(tripId: UUID) {
        store.deletePasses(tripId: tripId)
        NotificationCenter.default.post(name: .placesChanged, object: nil)
    }

    /// Место и проезды уходят; отметки остаются при своих `placeId` —
    /// надгробие, чтобы сверка не воскресила место тем же вечером. Новая
    /// отметка в той же ячейке заведёт его заново (тот же id).
    func delete(placeId: UUID) {
        store.deletePlace(id: placeId)
        reload()
        NotificationCenter.default.post(name: .placesChanged, object: nil)
    }

    // MARK: - Предфильтр

    private func candidatePlaces(for ref: TripPreviewRef?) -> [Place] {
        let all = store.fetchPlaces()
        guard !all.isEmpty, let ref else { return all.isEmpty ? [] : all }
        let cells = PlaceMatcher.cells(of: ref.previewCoordinates)
        return all.filter { PlaceMatcher.isCandidate(place: $0, tripCells: cells) }
    }
}
