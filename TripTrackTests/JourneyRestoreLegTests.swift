import XCTest
import CoreData
@testable import TripTrack

/// Возврат убранного плеча — единственное место, где `excludedTripIds`
/// УМЕНЬШАЕТСЯ.
///
/// До 0.6.6 список исключений только рос: «Убрать из путешествия» спрашивало
/// «точно?», зная, что назад хода нет. Сдвиг дат исключение не отменяет
/// (исключение сильнее окна), а собрать новое путешествие вокруг убранной
/// поездки не даёт проверка пересечения окон. Оставалось удалить путешествие и
/// собрать заново, потеряв имя и обложку.
///
/// Здесь проверяется обе половины возврата: что полка листа правки показывает
/// РОВНО те поездки, которые вернутся (`excludedTrips`), и что сам возврат —
/// это правка путешествия, то есть `pendingUpload` и очередь синка.
@MainActor
final class JourneyRestoreLegTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    override func tearDown() {
        repo = nil
        pc = nil
        super.tearDown()
    }

    @discardableResult
    private func trip(daysFromT0 d: Double) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.startDate = t0.addingTimeInterval(d * 86_400)
        e.endDate = e.startDate!.addingTimeInterval(3_600)
        e.distance = 100_000
        e.isPrivate = true
        try? ctx.save()
        return id
    }

    private func day(_ d: Double) -> Date { t0.addingTimeInterval(d * 86_400) }

    /// Ставит запись в «отправлено», чтобы следующая правка была видна: сам
    /// `saveJourney` взводит `pendingUpload` всегда.
    private func markSynced(_ id: UUID) {
        let ctx = pc.container.viewContext
        let req: NSFetchRequest<JourneyEntity> = JourneyEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        (try? ctx.fetch(req))?.first?.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
    }

    // MARK: - Полка

    func testRemovedLegsAreTheOnesInsideTheWindow() {
        let kept = trip(daysFromT0: 0)
        let removedEarly = trip(daysFromT0: 1)
        let removedLate = trip(daysFromT0: 2)
        let manager = JourneyManager(repository: repo)
        let journey = repo.saveJourney(Journey(
            startDate: day(0), endDate: day(3),
            excludedTripIds: [removedLate, removedEarly]))

        let shelf = manager.excludedTrips(in: journey)

        XCTAssertEqual(shelf.map(\.id), [removedEarly, removedLate],
                       "полка идёт по времени, а не в порядке убирания")
        XCTAssertFalse(shelf.contains { $0.id == kept }, "плечо в окне — не убранное")
    }

    /// Убранная поездка, которая после сдвига границ оказалась ВНЕ окна,
    /// возврату не подлежит: снятие исключения ей уже не поможет — дата
    /// отрежет её раньше. Карточка на полке обещала бы возврат, которого не
    /// будет.
    func testRemovedLegOutsideTheWindowIsNotOffered() {
        let inside = trip(daysFromT0: 0)
        let outside = trip(daysFromT0: 9)
        let manager = JourneyManager(repository: repo)
        let journey = repo.saveJourney(Journey(
            startDate: day(0), endDate: day(3),
            excludedTripIds: [inside, outside]))

        XCTAssertEqual(manager.excludedTrips(in: journey).map(\.id), [inside])
    }

    func testNothingRemovedMeansEmptyShelf() {
        trip(daysFromT0: 0)
        let manager = JourneyManager(repository: repo)
        let journey = repo.saveJourney(Journey(startDate: day(0), endDate: day(3)))

        XCTAssertTrue(manager.excludedTrips(in: journey).isEmpty)
    }

    // MARK: - Сам возврат

    func testReturningALegPutsItBackAsALeg() throws {
        let kept = trip(daysFromT0: 0)
        let removed = trip(daysFromT0: 1)
        let manager = JourneyManager(repository: repo)
        var journey = repo.saveJourney(Journey(
            startDate: day(0), endDate: day(3), excludedTripIds: [removed]))
        XCTAssertEqual(manager.trips(in: journey).map(\.id), [kept])

        journey.excludedTripIds.removeAll { $0 == removed }
        try manager.update(journey)

        let stored = try XCTUnwrap(manager.journeys.first { $0.id == journey.id })
        XCTAssertTrue(stored.excludedTripIds.isEmpty, "список исключений умеет уменьшаться")
        XCTAssertEqual(manager.trips(in: stored).map(\.id), [kept, removed],
                       "вернувшееся плечо встаёт на своё место по времени")
    }

    /// Возврат — правка путешествия, а не одна лишь перерисовка списка. Без
    /// `pendingUpload` он жил бы до первого pull: сервер вернул бы список с
    /// прежним исключением и «заменил целиком», как это уже было с отметками
    /// (`CheckpointSyncFlagTests`).
    func testReturningALegMarksTheJourneyForUpload() throws {
        let removed = trip(daysFromT0: 1)
        trip(daysFromT0: 0)
        let manager = JourneyManager(repository: repo)
        var journey = repo.saveJourney(Journey(
            startDate: day(0), endDate: day(3), excludedTripIds: [removed]))
        markSynced(journey.id)
        XCTAssertEqual(repo.journeySyncStatus(id: journey.id), SyncStatus.synced.rawValue)

        journey.excludedTripIds.removeAll { $0 == removed }
        try manager.update(journey)

        XCTAssertEqual(repo.journeySyncStatus(id: journey.id), SyncStatus.pendingUpload.rawValue)
    }

    /// Даты при возврате не двигаются, поэтому пересечься с соседним окном
    /// нечем — правка не имеет права отказать из-за чужих дат.
    func testReturningALegDoesNotCollideWithANeighbourJourney() throws {
        let removed = trip(daysFromT0: 1)
        trip(daysFromT0: 8)
        let manager = JourneyManager(repository: repo)
        var journey = repo.saveJourney(Journey(
            startDate: day(0), endDate: day(3), excludedTripIds: [removed]))
        _ = repo.saveJourney(Journey(startDate: day(7), endDate: day(9)))
        manager.reload()

        journey.excludedTripIds.removeAll { $0 == removed }
        XCTAssertNoThrow(try manager.update(journey))
    }
}
