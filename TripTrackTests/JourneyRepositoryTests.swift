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
}
