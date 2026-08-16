import XCTest
import CoreData
@testable import TripTrack

/// The heal is the second line, not the first. The store-identity stamp
/// catches "this is a different database"; this catches "this database is
/// short" — a partial loss inside a store whose identity never changed, which
/// no stamp can see.
final class SyncHealDecisionTests: XCTestCase {
    func testHealsWhenServerHasMoreTrips() {
        XCTAssertTrue(SyncCoordinator.shouldHeal(
            serverTrips: 107, localTrips: 0,
            latchedStoreIdentity: nil, currentStoreIdentity: "A"))
    }

    /// Bounded by construction: one heal per store, so a payload that never
    /// applies costs one extra full pull and then stops forever.
    func testDoesNotHealTwiceForTheSameStore() {
        XCTAssertFalse(SyncCoordinator.shouldHeal(
            serverTrips: 107, localTrips: 0,
            latchedStoreIdentity: "A", currentStoreIdentity: "A"))
    }

    /// A second wipe is a new store, and it is not silently written off.
    func testHealsAgainAfterANewStoreAppears() {
        XCTAssertTrue(SyncCoordinator.shouldHeal(
            serverTrips: 107, localTrips: 0,
            latchedStoreIdentity: "A", currentStoreIdentity: "B"))
    }

    func testDoesNotHealWhenCountsAgree() {
        XCTAssertFalse(SyncCoordinator.shouldHeal(
            serverTrips: 107, localTrips: 107,
            latchedStoreIdentity: nil, currentStoreIdentity: "A"))
    }

    /// Local ahead of the server is the OTHER reconciliation's business
    /// (re-push), and must not trigger a download-side heal.
    func testDoesNotHealWhenLocalIsAhead() {
        XCTAssertFalse(SyncCoordinator.shouldHeal(
            serverTrips: 100, localTrips: 107,
            latchedStoreIdentity: nil, currentStoreIdentity: "A"))
    }

    /// No store open means the local count is meaningless — healing against it
    /// would download the library into a database that is not being persisted.
    func testDoesNotHealWithoutAStoreIdentity() {
        XCTAssertFalse(SyncCoordinator.shouldHeal(
            serverTrips: 107, localTrips: 0,
            latchedStoreIdentity: nil, currentStoreIdentity: nil))
    }

    /// A brand-new install: nothing local, everything on the server. Same path,
    /// and the latch makes it a one-off.
    func testAFreshInstallHealsOnce() {
        XCTAssertTrue(SyncCoordinator.shouldHeal(
            serverTrips: 42, localTrips: 0,
            latchedStoreIdentity: nil, currentStoreIdentity: "fresh"))
        XCTAssertFalse(SyncCoordinator.shouldHeal(
            serverTrips: 42, localTrips: 0,
            latchedStoreIdentity: "fresh", currentStoreIdentity: "fresh"))
    }
}

final class SyncHealPopulationTests: XCTestCase {
    /// Counting `syncStatus == .synced` instead of live rows is a trap with a
    /// shipped trigger: `markAllPendingUpload()` flips EVERY trip during first
    /// sign-in and when Cloud Sync is switched on, and both then run a pull
    /// where `runPull` goes before `processQueue`. At that instant a
    /// synced-only count reads zero, and the device would heal against itself.
    ///
    /// A soft-deleted trip still mirrors a live server row, so it counts too —
    /// otherwise the heal pull revives a trip the user just deleted.
    func testLiveCountIgnoresSyncStatusAndCountsSoftDeleted() {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext

        for status in [SyncStatus.synced, .pendingUpload, .pendingUpload, .synced, .synced] {
            let e = TripEntity(context: ctx)
            e.id = UUID()
            e.startDate = Date()
            e.endDate = Date()
            e.syncStatus = status.rawValue
        }
        let deleted = TripEntity(context: ctx)
        deleted.id = UUID()
        deleted.startDate = Date()
        deleted.endDate = Date()
        deleted.syncStatus = SyncStatus.pendingDelete.rawValue

        XCTAssertEqual(repo.countLiveTrips(), 6)
    }

    /// A recording in progress has no `endDate` yet and is not part of the
    /// library the server knows about.
    func testAnInProgressRecordingIsNotCounted() {
        let pc = PersistenceController(inMemory: true)
        let repo = CoreDataTripRepository(persistenceController: pc)
        let ctx = pc.container.viewContext

        let finished = TripEntity(context: ctx)
        finished.id = UUID()
        finished.startDate = Date()
        finished.endDate = Date()

        let recording = TripEntity(context: ctx)
        recording.id = UUID()
        recording.startDate = Date()

        XCTAssertEqual(repo.countLiveTrips(), 1)
    }
}
