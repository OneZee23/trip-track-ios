import Foundation
import Combine

/// Путешествие — окно дат над своими поездками (0.6.6). CRUD и вычисление
/// кандидатов в плечи живут здесь, а не во вьюмодели: то же окно нужно и
/// экрану создания, и карточке в ленте.
@MainActor
final class JourneyManager: ObservableObject {
    static let shared = JourneyManager()
    @Published private(set) var journeys: [Journey] = []
    private let repository: TripRepository

    enum JourneyError: Error, Equatable {
        case empty
        case overlaps(UUID)
    }

    init(repository: TripRepository = CoreDataTripRepository()) {
        self.repository = repository
        reload()
    }

    func reload() { journeys = repository.fetchJourneys() }

    /// Окно — от первого старта до последнего финиша выбранных поездок.
    func create(from trips: [Trip], title: String?) throws -> Journey {
        let sorted = trips.sorted { $0.startDate < $1.startDate }
        guard let first = sorted.first, let last = sorted.last else { throw JourneyError.empty }
        let end = last.endDate ?? last.startDate
        if let clash = repository.journeyOverlapping(start: first.startDate, end: end, excluding: nil) {
            throw JourneyError.overlaps(clash.id)
        }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = repository.saveJourney(Journey(
            title: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            startDate: first.startDate, endDate: end))
        enqueue(saved.id, .upload)
        reload()
        return saved
    }

    func update(_ journey: Journey) throws {
        if let clash = repository.journeyOverlapping(start: journey.startDate, end: journey.endDate, excluding: journey.id) {
            throw JourneyError.overlaps(clash.id)
        }
        repository.saveJourney(journey)
        enqueue(journey.id, .update)
        reload()
    }

    /// Плечи остаются поездками — удаляется только обёртка.
    ///
    /// Синк путешествий (`SyncEnqueuer.shouldEnqueue`) — личные данные: с
    /// облаком выключенным `.journey` не уезжает НИКОГДА, поэтому строка
    /// `pendingDelete`, которую ставит `markJourneyDeleted`, никогда не
    /// дождётся подтверждения с сервера и не станет твёрдым удалением сама.
    /// `deleteVehicle` для этого случая просто не заводит мягкого удаления —
    /// здесь мягкое удаление нужно (оно и прячет путешествие из ленты, пока
    /// синк идёт), так что вместо этого твёрдое удаление зовётся сразу,
    /// когда ждать подтверждения всё равно не от кого.
    func delete(id: UUID) {
        repository.markJourneyDeleted(id: id)
        enqueue(id, .delete)
        if !SettingsManager.shared.cloudSyncEnabled {
            repository.deleteJourneyHard(id: id)
        }
        reload()
    }

    func journey(containing tripId: UUID) -> Journey? { repository.journeyContaining(tripId: tripId) }
    func trips(in journey: Journey) -> [Trip] { repository.trips(in: journey) }

    /// Соседи по времени, ещё ни в каком путешествии: кандидаты в плечи —
    /// соседи, без самой поездки: её экран ставит первой сам.
    func neighbours(of trip: Trip, days: Int = 7) -> [Trip] {
        let window = TimeInterval(days * 86_400)
        return repository.fetchAllTrips()
            .filter { $0.id != trip.id }
            .filter { abs($0.startDate.timeIntervalSince(trip.startDate)) <= window }
            .filter { repository.journeyContaining(tripId: $0.id) == nil }
            .sorted { $0.startDate < $1.startDate }
    }

    private func enqueue(_ id: UUID, _ action: SyncOperation.Action) {
        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: id, action: action))
    }
}
