import XCTest
import CoreData
@testable import TripTrack

/// Черновик в мир не выходит (спека §3.2): «мировые» выборки идут через один
/// предикат, история читает черновики отдельно.
@MainActor
final class DraftIsolationTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        defaults = UserDefaults(suiteName: "DraftIsolationTests")
        defaults.removePersistentDomain(forName: "DraftIsolationTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "DraftIsolationTests")
        defaults = nil
        repo = nil
        pc = nil
        super.tearDown()
    }

    /// Поездка на 300 м к северу, сдвинутая на `east` метров.
    private func trip(_ c: TripConfirmation, east: Double = 0) -> UUID {
        TrackTestKit.insertTrip(into: pc, points: (0...30).map {
            .init(east: east, north: Double($0) * 10, seconds: Double($0))
        }, processed: true, confirmation: c).id!
    }

    private func checkpoint() -> TripCheckpoint {
        TripCheckpoint(timestamp: TrackTestKit.epoch.addingTimeInterval(5),
                       latitude: TrackTestKit.origin.latitude, longitude: TrackTestKit.origin.longitude,
                       distanceFromStart: 50, elapsedFromStart: 5, name: nil)
    }

    func testWorldReadsNeverSeeADraft() {
        let draft = trip(.draft)
        let real = trip(.confirmed)
        XCTAssertEqual(repo.fetchAllTrips().map(\.id), [real])
        XCTAssertFalse(repo.fetchTrips(from: .distantPast, to: .distantFuture).contains { $0.id == draft })
        XCTAssertFalse(repo.tripPreviews(needingPlaceMatch: false).contains { $0.id == draft })
        XCTAssertEqual(repo.fetchTripStats().count, 1)
        XCTAssertEqual(repo.countLiveTrips(), 1, "на сервере черновика не бывает — размер библиотеки без него")
    }

    func testHistoryAndTheTripScreenStillSeeIt() {
        let draft = trip(.draft)
        XCTAssertEqual(repo.fetchDraftTrips().map(\.id), [draft])
        XCTAssertEqual(repo.fetchTripDetail(id: draft)?.isDraft, true)
    }

    func testRevealLayerNeverReadsADraftPreview() throws {
        let draft = trip(.draft)
        let real = trip(.confirmed)
        for id in [draft, real] {
            repo.fetchEntity(id: id)?.previewPolyline = Trip.encodePolyline([
                TrackTestKit.coordinate(east: 0, north: 0), TrackTestKit.coordinate(east: 0, north: 300)])
        }
        try pc.container.viewContext.save()
        let rows = try pc.container.viewContext.fetch(RevealedLayerStore.previewRequest(endedBefore: nil))
        XCTAssertEqual(rows.compactMap { $0["id"] as? UUID }, [real])
    }

    func testDraftCheckpointIsNotAnOrphanForPlaces() {
        let draft = trip(.draft)
        _ = repo.addCheckpoint(checkpoint(), to: draft)
        XCTAssertTrue(repo.checkpointsWithoutPlace().isEmpty)
    }

    func testADraftCheckpointMakesNoPlaceUntilConfirmed() throws {
        let draft = trip(.draft)
        let cp = checkpoint()
        _ = repo.addCheckpoint(cp, to: draft)
        let manager = PlaceManager(repository: repo, store: CoreDataPlaceStore(context: pc.container.viewContext))
        manager.pendingHistoryIds = []
        defer { manager.pendingHistoryIds = [] }

        manager.registerCheckpoint(cp, tripId: draft)
        XCTAssertTrue(manager.places.isEmpty, "у слоя мест нет отката — черновик в него не входит")

        repo.fetchEntity(id: draft)?.confirmation = TripConfirmation.confirmed.rawValue
        try pc.container.viewContext.save()
        manager.registerCheckpoint(cp, tripId: draft)
        XCTAssertEqual(manager.places.count, 1)
    }

    /// Территория — это «города и регионы» в статистике: черновик не красит её.
    func testTerritoryBackfillSkipsDraftPoints() async {
        _ = trip(.confirmed)
        _ = trip(.draft, east: 30_000)   // тридцать километров в стороне — свои ячейки
        let tm = TerritoryManager(persistenceController: pc, defaults: defaults)
        await tm.backfillIfNeeded()
        let far = TrackTestKit.coordinate(east: 30_000, north: 0)
        let draftCell = GeohashEncoder.encode(latitude: far.latitude, longitude: far.longitude, precision: 6)
        XCTAssertFalse(tm.visitedGeohashes.isEmpty)
        XCTAssertFalse(tm.visitedGeohashes.contains(draftCell))
    }
}
