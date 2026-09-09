import XCTest
import CoreData
@testable import TripTrack

/// `JourneyManager` — CRUD над окном дат плюс подбор кандидатов в плечи.
/// Репозиторий уже проверен в `JourneyRepositoryTests`; здесь — то, что
/// добавляет сам менеджер: сборка окна из выбранных поездок, отказ на
/// пересечении дат, соседи по времени.
@MainActor
final class JourneyManagerTests: XCTestCase {
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

    private func fetchTrip(_ id: UUID) -> Trip {
        // Force-unwrap: тестовая опора, а не восстановимая ошибка — если
        // поездки нет, тест-хелпер сам сломан.
        repo.fetchAllTrips().first(where: { $0.id == id })!
    }

    func testNeighboursAreWithinAWeekAndNotAlreadyInAJourney() {
        let anchorId = trip(daysFromT0: 0)
        let beforeId = trip(daysFromT0: -2)
        let afterId = trip(daysFromT0: 3)
        let farId = trip(daysFromT0: 20)
        let takenId = trip(daysFromT0: 1)

        // `takenId` уже внутри своего путешествия — не кандидат в чужое.
        repo.saveJourney(Journey(
            startDate: t0.addingTimeInterval(1 * 86_400),
            endDate: t0.addingTimeInterval(1 * 86_400 + 3_600)))

        let manager = JourneyManager(repository: repo)
        let anchor = fetchTrip(anchorId)
        let neighbourIds = Set(manager.neighbours(of: anchor).map(\.id))

        XCTAssertTrue(neighbourIds.contains(beforeId), "-2 дня — сосед")
        XCTAssertTrue(neighbourIds.contains(afterId), "+3 дня — сосед")
        XCTAssertFalse(neighbourIds.contains(farId), "+20 дней — вне недели")
        XCTAssertFalse(neighbourIds.contains(takenId), "уже в путешествии — не кандидат")
        XCTAssertFalse(neighbourIds.contains(anchorId), "сама поездка — не сосед себе")
    }

    func testCreateBuildsTheWindowFromFirstStartToLastEnd() throws {
        let firstId = trip(daysFromT0: 0)
        let lastId = trip(daysFromT0: 2)
        let manager = JourneyManager(repository: repo)
        // Порядок передачи — вперемешку: сборка окна не должна полагаться
        // на то, что вызывающий код уже отсортировал плечи.
        let trips = [fetchTrip(lastId), fetchTrip(firstId)]

        let journey = try manager.create(from: trips, title: "   ")

        XCTAssertEqual(journey.startDate, fetchTrip(firstId).startDate)
        XCTAssertEqual(journey.endDate, fetchTrip(lastId).endDate)
        XCTAssertNil(journey.title, "пустой (пробельный) заголовок сохраняется как nil")
    }

    func testCreateRefusesOverlap() throws {
        let aId = trip(daysFromT0: 0)
        let bId = trip(daysFromT0: 1)
        let manager = JourneyManager(repository: repo)
        let trips = [fetchTrip(aId), fetchTrip(bId)]

        _ = try manager.create(from: trips, title: "Первое")

        XCTAssertThrowsError(try manager.create(from: trips, title: "Второе")) { error in
            guard case JourneyManager.JourneyError.overlaps = error else {
                XCTFail("expected .overlaps, got \(error)")
                return
            }
        }
    }
}
