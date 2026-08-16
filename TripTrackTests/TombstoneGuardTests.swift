import XCTest
import CoreData
@testable import TripTrack

/// `PullApplier` used to hard-delete on every id in `trips.deleted`, and
/// `applyRemoteTrip` never stamped `serverCreatedAt` — so every trip that
/// arrived by pull carried nil, and a tombstone meant for the server's copy
/// destroyed the local original.
///
/// The two halves have to land together. The guard alone would make pulled
/// trips undeletable from any other device forever, and `reconcileAfterPull`
/// would then notice them missing from the manifest and re-upload them:
/// zombie trips, created by the safety feature.
final class TombstoneGuardTests: XCTestCase {
    private var pc: PersistenceController!
    private var repo: CoreDataTripRepository!

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
    private func insertTrip(serverCreatedAt: Date?) -> TripEntity {
        let e = TripEntity(context: pc.container.viewContext)
        e.id = UUID()
        e.startDate = Date()
        e.endDate = Date()
        e.serverCreatedAt = serverCreatedAt
        e.syncStatus = SyncStatus.synced.rawValue
        return e
    }

    private static func payload(
        id: UUID, serverCreatedAt: Date?, conflictVersion: Int = 1,
        lastModifiedAt: Date = Date()
    ) -> TripSyncPayload {
        TripSyncPayload(
            id: id, title: "t", description: nil,
            startDate: Date(), endDate: Date(),
            distance: 1000, maxSpeed: 20, averageSpeed: 15, fuelUsed: 0, elevation: 0,
            maxAltitude: nil, drivingTime: nil, stoppedTime: nil, region: nil,
            isPrivate: true, vehicleId: nil, fuelCurrency: nil, previewPolyline: nil,
            badgesJson: nil, xpEarned: 0,
            conflictVersion: conflictVersion, lastModifiedAt: lastModifiedAt,
            serverCreatedAt: serverCreatedAt, trackPoints: nil, photos: nil)
    }

    /// A trip that lives only on this phone — including one the user
    /// un-published, because `markUnpublished` clears the column on purpose.
    func testATombstoneDoesNotDeleteATripTheServerNeverHad() {
        let trip = insertTrip(serverCreatedAt: nil)
        let id = trip.id!

        XCTAssertFalse(repo.deleteTripHardIfMirrored(id: id))
        XCTAssertNotNil(repo.fetchEntity(id: id), "an unmirrored trip must survive a tombstone")
    }

    /// The guard must not amount to switching remote deletion off.
    func testATombstoneDeletesAMirroredTrip() {
        let trip = insertTrip(serverCreatedAt: Date())
        let id = trip.id!

        XCTAssertTrue(repo.deleteTripHardIfMirrored(id: id))
        XCTAssertNil(repo.fetchEntity(id: id))
    }

    /// Without this, the guard above is permanent for every pulled trip.
    func testAPulledTripRemembersThatTheServerHasIt() {
        let p = Self.payload(id: UUID(), serverCreatedAt: Date())
        repo.applyRemoteTrip(p)
        XCTAssertNotNil(repo.fetchEntity(id: p.id)?.serverCreatedAt)
    }

    /// An older server omits the field, but sending the trip at all is itself
    /// the statement that the server has it.
    func testAPayloadWithoutServerCreatedAtStillStamps() {
        let p = Self.payload(id: UUID(), serverCreatedAt: nil)
        repo.applyRemoteTrip(p)
        XCTAssertNotNil(repo.fetchEntity(id: p.id)?.serverCreatedAt)
    }

    func testApplyRemoteTripDoesNotOverwriteAnExistingServerCreatedAt() {
        let known = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = insertTrip(serverCreatedAt: known)

        repo.applyRemoteTrip(Self.payload(id: trip.id!, serverCreatedAt: Date()))

        XCTAssertEqual(trip.serverCreatedAt, known)
    }

    /// 0.6.1 forces one full pull on every device. On a full pull a
    /// soft-deleted trip is still a live server row — without `pendingDelete`
    /// in the skip-guard the upgrade itself would undo the user's deletion.
    func testAFullPullDoesNotResurrectASoftDeletedTrip() {
        let trip = insertTrip(serverCreatedAt: Date())
        trip.syncStatus = SyncStatus.pendingDelete.rawValue
        trip.conflictVersion = 5

        repo.applyRemoteTrip(Self.payload(id: trip.id!, serverCreatedAt: Date(), conflictVersion: 5))

        XCTAssertEqual(trip.syncStatus, SyncStatus.pendingDelete.rawValue,
                       "a deliberately deleted trip must not come back as .synced")
    }

    /// The photo half: `/trips/delete` cascades onto photo rows, so the same
    /// pull carries their ids. A trip we kept must keep its gallery.
    func testTripIdForPhotoResolvesTheParent() {
        let trip = insertTrip(serverCreatedAt: nil)
        let photo = TripPhotoEntity(context: pc.container.viewContext)
        photo.id = UUID()
        photo.filename = "p.jpg"
        photo.timestamp = Date()
        photo.trip = trip

        XCTAssertEqual(repo.tripId(forPhoto: photo.id!), trip.id)
    }
}
