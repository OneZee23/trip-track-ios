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
    private var cancellables = Set<AnyCancellable>()

    enum JourneyError: Error, Equatable {
        case empty
        case overlaps(UUID)
        case notFound
    }

    init(repository: TripRepository = CoreDataTripRepository()) {
        self.repository = repository
        reload()
        // Путешествие, созданное на другом телефоне, приезжает пулом прямо в
        // CoreData — минуя всё, что зовёт `reload()` руками. Без этой строки
        // список в памяти оставался бы вчерашним до перезапуска: карточки нет,
        // а окно дат уже занято, и «Объединить» на тех же поездках отвечает
        // «даты заняты другим путешествием», которого человек не видит.
        NotificationCenter.default.publisher(for: .syncPullCompleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.reload()
            }
            .store(in: &cancellables)
    }

    func reload() { journeys = repository.fetchJourneys() }

    /// Окно — от первого старта до последнего финиша выбранных поездок.
    ///
    /// Снятая галочка — это ответ, а не пустое место. Окно берёт ВСЕ свои
    /// поездки внутри границ, поэтому сосед, которого человек только что убрал
    /// в листе создания, вернулся бы плечом сразу после сохранения. Он и
    /// возвращался: список приходит уже отфильтрованным, а в базу уезжали одни
    /// даты. Поэтому здесь же, на создании, снятые пишутся в `excludedTripIds`
    /// — единственное место, где «внутри окна» и «в путешествии» расходятся.
    func create(from trips: [Trip], title: String?) throws -> Journey {
        let sorted = trips.sorted { $0.startDate < $1.startDate }
        guard let first = sorted.first, let last = sorted.last else { throw JourneyError.empty }
        let end = last.endDate ?? last.startDate
        if let clash = repository.journeyOverlapping(start: first.startDate, end: end, excluding: nil) {
            throw JourneyError.overlaps(clash.id)
        }
        let chosen = Set(sorted.map(\.id))
        // Окно уже известно — значит и спрашивать надо его, а не библиотеку:
        // выборка режется предикатом в базе (`fetchTrips(from:to:)`).
        let excluded = repository.fetchTrips(from: first.startDate, to: end)
            .filter { !chosen.contains($0.id) }
            .sorted { $0.startDate < $1.startDate }
            .map(\.id)
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = repository.saveJourney(Journey(
            title: (trimmed?.isEmpty ?? true) ? nil : trimmed,
            startDate: first.startDate, endDate: end,
            excludedTripIds: excluded))
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
        // Очередь — FIFO, и невыстрелившая `.upload`/`.update` того же
        // путешествия ушла бы на сервер за мгновение до его же `.delete`:
        // сервер увидел бы запись, которой у человека уже нет, а на втором
        // телефоне она успела бы моргнуть карточкой. Ровно то же делает
        // удаление поездки (`TripManager.deleteTrip`).
        SyncQueue.shared.cancelOperations(for: id, entityType: .journey)
        enqueue(id, .delete)
        if !SettingsManager.shared.cloudSyncEnabled {
            repository.deleteJourneyHard(id: id)
        }
        reload()
    }

    /// Плечи, которые публикация ОТКРОЕТ: приватные поездки окна. Лист S5
    /// показывает ровно их, кнопка считает ровно их.
    func privateLegs(in journey: Journey) -> [Trip] {
        trips(in: journey).filter(\.isPrivate)
    }

    /// Публикация открывает плечи (правило владельца): каждое приватное плечо
    /// проходит через СВОЙ `updatePrivacy` — он же ставит поездку и снимки в
    /// очередь синка, — и только потом путешествие становится публичным. Не
    /// наоборот: публичное путешествие без плеч на сервере — пустая карточка.
    func publish(id: UUID, tripManager: TripManager) throws {
        guard var journey = journeys.first(where: { $0.id == id }) else { throw JourneyError.notFound }
        for leg in privateLegs(in: journey) {
            tripManager.updatePrivacy(for: leg.id, isPrivate: false)
        }
        journey.isPrivate = false
        journey.lastModifiedAt = Date()
        repository.saveJourney(journey)
        // Всегда `.upload`: `saveJourney` только что безусловно поставила
        // `syncStatus = .pendingUpload`, так что спрашивать статус после неё
        // нечего, а `(.journey, .upload)` и `(.journey, .update)` — одна
        // ветка транспорта.
        enqueue(id, .upload)
        reload()
    }

    /// Скрытие — только само путешествие: сервер хранит строку и перестаёт
    /// отдавать её. Плечи не трогаем — обратное правило несимметрично.
    /// `.unpublish`, а не `.update`: гейт синка пропускает его и без облака,
    /// а транспорт для путешествия делает по нему апсерт с `isPrivate = true`.
    func hide(id: UUID) {
        guard var journey = journeys.first(where: { $0.id == id }) else { return }
        journey.isPrivate = true
        journey.lastModifiedAt = Date()
        repository.saveJourney(journey)
        SyncQueue.shared.cancelOperations(for: id, entityType: .journey)
        enqueue(id, .unpublish)
        reload()
    }

    func journey(containing tripId: UUID) -> Journey? { repository.journeyContaining(tripId: tripId) }
    func trips(in journey: Journey) -> [Trip] { repository.trips(in: journey) }

    /// Плечи, убранные рукой: те, что ВЕРНУТСЯ в окно, если снять исключение.
    ///
    /// Окно то же самое, что у `trips(in:)`, — потому что оно и спрашивается,
    /// у той же функции, с пустым списком исключений. Убранная поездка, чей
    /// старт лежит за границами, в ответ не попадает: снятие исключения ей
    /// уже не поможет (`Journey.contains` отрежет её датой), а карточка в
    /// листе правки обещала бы возврат, которого не будет.
    func excludedTrips(in journey: Journey) -> [Trip] {
        guard !journey.excludedTripIds.isEmpty else { return [] }
        let removed = Set(journey.excludedTripIds)
        var window = journey
        window.excludedTripIds = []
        return repository.trips(in: window).filter { removed.contains($0.id) }
    }

    /// Соседи по времени, ещё ни в каком путешествии: кандидаты в плечи —
    /// соседи, без самой поездки: её экран ставит первой сам.
    ///
    /// Обе выборки — по разу на весь список, и это существенно. Раньше сюда
    /// поднималась ВСЯ библиотека (`fetchAllTrips`, со снимками и отметками
    /// каждой поездки), а потом на каждого уцелевшего кандидата звался
    /// `journeyContaining`, который внутри заново перечитывал путешествия. Всё
    /// это — синхронно, на главном потоке: лист объединения замирал ровно у
    /// тех, кто ездит давно. Теперь окно отрезает база, а членство считает
    /// `Journey.contains` по одному разу вычитанному списку путешествий —
    /// правило то же самое, что было у `journeyContaining`.
    func neighbours(of trip: Trip, days: Int = 7) -> [Trip] {
        let window = TimeInterval(days * 86_400)
        let existing = repository.fetchJourneys()
        return repository.fetchTrips(from: trip.startDate.addingTimeInterval(-window),
                                     to: trip.startDate.addingTimeInterval(window))
            .filter { $0.id != trip.id }
            .filter { candidate in !existing.contains { $0.contains(candidate) } }
            .sorted { $0.startDate < $1.startDate }
    }

    private func enqueue(_ id: UUID, _ action: SyncOperation.Action) {
        SyncEnqueuer.enqueue(SyncOperation(entityType: .journey, entityId: id, action: action))
    }
}
