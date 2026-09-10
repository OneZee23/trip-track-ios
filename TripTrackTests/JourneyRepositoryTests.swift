import XCTest
import CoreData
@testable import TripTrack

/// Путешествие — окно дат: плечи вычисляются, а не хранятся.
final class JourneyRepositoryTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
    }

    @discardableResult
    private func trip(daysFromT0 d: Double, km: Double = 100) -> UUID {
        let ctx = pc.container.viewContext
        let e = TripEntity(context: ctx)
        let id = UUID()
        e.id = id
        e.startDate = t0.addingTimeInterval(d * 86_400)
        e.endDate = e.startDate!.addingTimeInterval(3_600)
        e.distance = km * 1_000
        e.isPrivate = true
        try? ctx.save()
        return id
    }

    func testTripsInsideTheWindowAreTheLegs() {
        let a = trip(daysFromT0: 0), b = trip(daysFromT0: 1), _ = trip(daysFromT0: 9)
        let j = repo.saveJourney(Journey(startDate: t0, endDate: t0.addingTimeInterval(3 * 86_400)))
        XCTAssertEqual(Set(repo.trips(in: j).map(\.id)), [a, b])
        XCTAssertEqual(repo.fetchJourneys().map(\.id), [j.id])
    }

    /// Окно отрезает БАЗА, а не фильтр в памяти — и отрезает ровно по
    /// границам: поездка, стартовавшая в тот самый день, что и край окна,
    /// внутри, а соседи снаружи остаются снаружи.
    func testFetchTripsInWindowKeepsTheBoundariesAndDropsTheNeighbours() {
        let ids = (0..<10).map { trip(daysFromT0: Double($0)) }

        let window = repo.fetchTrips(from: t0.addingTimeInterval(3 * 86_400),
                                     to: t0.addingTimeInterval(5 * 86_400))

        XCTAssertEqual(window.map(\.id), [ids[3], ids[4], ids[5]],
                       "три дня окна включительно, по старту и по возрастанию")
    }

    func testExcludedTripLeavesTheJourney() {
        let a = trip(daysFromT0: 0), b = trip(daysFromT0: 1)
        var j = repo.saveJourney(Journey(startDate: t0, endDate: t0.addingTimeInterval(2 * 86_400)))
        j.excludedTripIds = [b]
        j = repo.saveJourney(j)
        XCTAssertEqual(repo.trips(in: j).map(\.id), [a])
        XCTAssertEqual(repo.journeyContaining(tripId: a)?.id, j.id)
        XCTAssertNil(repo.journeyContaining(tripId: b))
    }

    func testOverlappingWindowIsDetected() {
        let j = repo.saveJourney(Journey(startDate: t0, endDate: t0.addingTimeInterval(2 * 86_400)))
        XCTAssertEqual(repo.journeyOverlapping(
            start: t0.addingTimeInterval(86_400), end: t0.addingTimeInterval(5 * 86_400), excluding: nil)?.id, j.id)
        XCTAssertNil(repo.journeyOverlapping(
            start: t0.addingTimeInterval(3 * 86_400), end: t0.addingTimeInterval(5 * 86_400), excluding: nil))
        XCTAssertNil(repo.journeyOverlapping(start: t0, end: t0.addingTimeInterval(86_400), excluding: j.id))
    }

    func testSavingFlipsPendingUploadAndSoftDeleteHidesIt() {
        let j = repo.saveJourney(Journey(startDate: t0, endDate: t0))
        XCTAssertEqual(repo.journeySyncStatus(id: j.id), SyncStatus.pendingUpload.rawValue)
        repo.markJourneyDeleted(id: j.id)
        XCTAssertTrue(repo.fetchJourneys().isEmpty, "pendingDelete прячется из UI")
        repo.deleteJourneyHard(id: j.id)
        XCTAssertNil(repo.fetchJourney(id: j.id))
    }

    /// Путешествие, приехавшее с сервера впервые, приземляется как `synced` —
    /// иначе очередь тут же попыталась бы отправить его обратно.
    func testApplyRemoteJourneyLandsAsSynced() {
        let id = UUID()
        let payload = JourneySyncPayload(journey: Journey(
            id: id, title: "Юг", startDate: t0, endDate: t0.addingTimeInterval(2 * 86_400)))
        repo.applyRemoteJourney(payload)
        repo.flushPendingApplies()
        XCTAssertEqual(repo.journeySyncStatus(id: id), SyncStatus.synced.rawValue)
        XCTAssertEqual(repo.fetchJourney(id: id)?.title, "Юг")
    }

    /// Локальная правка, ещё не уехавшая, старше серверной копии — pull не
    /// имеет права её переписать (иначе локальные правки терялись бы на
    /// каждом фоновом пуле, который выигрывает гонку с очередью).
    func testApplyRemoteJourneyDoesNotOverwritePendingUpload() {
        let local = repo.saveJourney(Journey(title: "Местное имя", startDate: t0, endDate: t0))
        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingUpload.rawValue)

        let remote = JourneySyncPayload(journey: Journey(
            id: local.id, title: "Серверное имя", startDate: t0, endDate: t0))
        repo.applyRemoteJourney(remote)
        repo.flushPendingApplies()

        XCTAssertEqual(repo.journeySyncStatus(id: local.id), SyncStatus.pendingUpload.rawValue)
        XCTAssertEqual(repo.fetchJourney(id: local.id)?.title, "Местное имя")
    }
}
