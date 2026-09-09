import XCTest
import CoreData
@testable import TripTrack

/// Отметки едут на сервер внутри поездки. Значит правка отметки — правка
/// поездки, и репозиторий обязан взвести `pendingUpload`, иначе очередь синка
/// её не увидит, а следующий pull заменит локальный список серверным и сотрёт
/// то, что человек только что поставил. Ревью 8 сентября 2026 нашло ровно это.
final class CheckpointSyncFlagTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!
    private var tripId: UUID!

    override func setUp() {
        super.setUp()
        pc = PersistenceController(inMemory: true)
        repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext
        let trip = TripEntity(context: ctx)
        tripId = UUID()
        trip.id = tripId
        trip.startDate = Date()
        trip.endDate = Date()
        trip.isPrivate = false           // публичная — уходит на сервер и без облака
        trip.syncStatus = SyncStatus.synced.rawValue
        try? ctx.save()
    }

    private var status: Int16? { repo.fetchEntity(id: tripId)?.syncStatus }

    private func checkpoint() -> TripCheckpoint {
        TripCheckpoint(timestamp: Date(), latitude: 45, longitude: 38.9,
                       distanceFromStart: 1_000, elapsedFromStart: 60)
    }

    func testAddingACheckpointMarksTheTripForUpload() {
        XCTAssertNotNil(repo.addCheckpoint(checkpoint(), to: tripId))
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
    }

    func testRenamingACheckpointMarksTheTripForUpload() {
        let saved = repo.addCheckpoint(checkpoint(), to: tripId)!
        repo.fetchEntity(id: tripId)?.syncStatus = SyncStatus.synced.rawValue
        XCTAssertEqual(repo.updateCheckpoint(id: saved.id, name: "Джубга", photoId: nil, photoIds: []), tripId)
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
    }

    func testDeletingACheckpointMarksTheTripForUpload() {
        let saved = repo.addCheckpoint(checkpoint(), to: tripId)!
        repo.fetchEntity(id: tripId)?.syncStatus = SyncStatus.synced.rawValue
        XCTAssertEqual(repo.deleteCheckpoint(id: saved.id), tripId)
        XCTAssertEqual(status, SyncStatus.pendingUpload.rawValue)
        XCTAssertEqual(repo.fetchEntity(id: tripId)?.checkpoints?.count ?? 0, 0)
    }

    /// Отметки, которой нет, — нет и поездки: очередь не должна получать мусор.
    func testUnknownCheckpointReturnsNoTrip() {
        XCTAssertNil(repo.updateCheckpoint(id: UUID(), name: nil, photoId: nil, photoIds: []))
        XCTAssertNil(repo.deleteCheckpoint(id: UUID()))
    }
}
