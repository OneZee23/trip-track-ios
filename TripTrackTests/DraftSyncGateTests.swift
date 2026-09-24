import XCTest
import CoreData
@testable import TripTrack

/// Черновик не уезжает на сервер ни при каком облаке (спека §3.2), и его
/// снимки тоже.
@MainActor
final class DraftSyncGateTests: XCTestCase {
    private var created: [TripEntity] = []

    override func tearDown() {
        let ctx = PersistenceController.shared.container.viewContext
        created.forEach(ctx.delete)
        try? ctx.save()
        created = []
        super.tearDown()
    }

    private func draft() -> TripEntity {
        let entity = TrackTestKit.insertTrip(into: .shared, points: [
            .init(east: 0, north: 0, seconds: 0), .init(east: 0, north: 10, seconds: 1),
        ], processed: true, confirmation: .draft)
        created.append(entity)
        return entity
    }

    func testEnqueuerRefusesADraftUntilItIsConfirmed() throws {
        let entity = draft()
        let op = SyncOperation(entityType: .trip, entityId: try XCTUnwrap(entity.id), action: .upload)
        XCTAssertTrue(SyncEnqueuer.isDraftTrip(op))

        entity.confirmation = TripConfirmation.confirmed.rawValue
        XCTAssertFalse(SyncEnqueuer.isDraftTrip(op))
    }

    func testDeleteIsNeverBlocked() throws {
        let op = SyncOperation(entityType: .trip, entityId: try XCTUnwrap(draft().id), action: .delete)
        XCTAssertFalse(SyncEnqueuer.isDraftTrip(op))
    }
}
