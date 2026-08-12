import XCTest
import CoreData
@testable import TripTrack

/// Coverage for Fix 4 (companions review) — the on-device companions cache
/// (`TripEntity.companionsJSON`, written by `TripRepository.updateCompanions`
/// after every successful `/companions/list` on one of the viewer's OWN
/// trips) is per-account data. Local trips themselves are device-scoped
/// (`TripEntity.userId` is `SettingsManager.localUserId`, which does NOT
/// change across a sign-out/sign-in), so they survive an account switch on
/// their own — but the roster cached on them reflects whichever account was
/// signed in when it was last fetched. Without a sign-out wipe, the next
/// account on the same device would see the PREVIOUS account's cached
/// roster on any of THEIR OWN trips until that trip's card happened to
/// re-fetch. `CompanionsStore.clear()` alone does not close this — it only
/// wipes IN-MEMORY state, never the CoreData column.
///
/// `AuthService` has no injectable repository, so this runs against the
/// SHARED `PersistenceController` — same convention `CompanionPhotoUploadTests`
/// uses for the shared store's orphan-row counts — with the fixture
/// inserted and torn down explicitly.
@MainActor
final class CompanionsCacheSignOutTests: XCTestCase {

    private var insertedTripId: UUID?

    override func setUp() {
        super.setUp()
        // `TokenStore` is Keychain-backed and outlives any single test —
        // some OTHER suite in the same process can leave a token behind.
        // Clearing it here makes `signOut()`'s network branch
        // deterministically skipped (see the call sites below) regardless
        // of what ran before this test, rather than merely ASSUMING no
        // token exists.
        TokenStore.shared.clear()
    }

    override func tearDown() {
        if let id = insertedTripId {
            let ctx = PersistenceController.shared.container.viewContext
            let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try? ctx.fetch(req).first {
                ctx.delete(entity)
                try? ctx.save()
            }
        }
        insertedTripId = nil
        super.tearDown()
    }

    /// THE regression this suite exists to catch: signing out must wipe
    /// `companionsJSON` from every local trip, not just the in-memory
    /// `CompanionsStore`. Fails if `AuthService.clearLocalIdentity` stops
    /// calling `CoreDataTripRepository().clearCompanionsCache()`.
    func testSignOut_ClearsCompanionsJSONOnLocalTrip() async throws {
        let ctx = PersistenceController.shared.container.viewContext
        let tripId = UUID()
        insertedTripId = tripId
        // `NSEntityDescription.insertNewObject(forEntityName:into:)`, not
        // the generated `TripEntity(context:)` convenience init: this test
        // touches the SHARED, on-disk-backed `PersistenceController` (the
        // same one `AuthService` uses in production — there's no
        // injectable repository to substitute), and by the time this test
        // runs, several OTHER suites have already constructed and torn
        // down their OWN isolated in-memory `PersistenceController`s. Core
        // Data resolves `TripEntity(context:)` via a process-wide `+entity`
        // class-to-model cache that those earlier, independently-loaded
        // `NSManagedObjectModel` instances can leave pointed at a stale
        // model — a real, independently-documented Core Data pitfall,
        // observed here as an intermittent
        // `NSPersistentStoreIncompatibleVersionHashError` ("model
        // configuration ... incompatible with the one used to create the
        // store") on save. Asking the CONTEXT's own coordinator for the
        // entity description by name sidesteps that global cache entirely.
        let entity = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx) as! TripEntity
        entity.id = tripId
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.distance = 1000
        entity.isPrivate = true
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = Date()
        entity.companionsJSON = #"[{"accountId":"\#(UUID().uuidString)","displayName":"Аня","avatarEmoji":"🙂","status":1}]"#
        try ctx.save()
        XCTAssertNotNil(entity.companionsJSON, "sanity: the cache is actually populated before sign-out")

        // Safe to call directly: `setUp` cleared `TokenStore`, so
        // `signOut()` skips the `/auth/logout` network call entirely and
        // runs straight to the local cleanup this test is pinning.
        XCTAssertNil(TokenStore.shared.accessToken, "sanity: no network call will be attempted")
        await AuthService.shared.signOut()

        XCTAssertNil(entity.companionsJSON, "the companions cache must not survive sign-out")
    }

    /// Baseline: a trip that never had a cache (`companionsJSON == nil`,
    /// the far more common case — most trips are never a viewer's own
    /// server-tracked companion roster) must not be disturbed by the wipe
    /// — no crash, no spurious write, still nil afterward.
    func testSignOut_LeavesTripWithNoCacheUntouched() async throws {
        let ctx = PersistenceController.shared.container.viewContext
        let tripId = UUID()
        insertedTripId = tripId
        // `NSEntityDescription.insertNewObject(forEntityName:into:)`, not
        // the generated `TripEntity(context:)` convenience init: this test
        // touches the SHARED, on-disk-backed `PersistenceController` (the
        // same one `AuthService` uses in production — there's no
        // injectable repository to substitute), and by the time this test
        // runs, several OTHER suites have already constructed and torn
        // down their OWN isolated in-memory `PersistenceController`s. Core
        // Data resolves `TripEntity(context:)` via a process-wide `+entity`
        // class-to-model cache that those earlier, independently-loaded
        // `NSManagedObjectModel` instances can leave pointed at a stale
        // model — a real, independently-documented Core Data pitfall,
        // observed here as an intermittent
        // `NSPersistentStoreIncompatibleVersionHashError` ("model
        // configuration ... incompatible with the one used to create the
        // store") on save. Asking the CONTEXT's own coordinator for the
        // entity description by name sidesteps that global cache entirely.
        let entity = NSEntityDescription.insertNewObject(forEntityName: "TripEntity", into: ctx) as! TripEntity
        entity.id = tripId
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.distance = 500
        entity.isPrivate = true
        entity.syncStatus = SyncStatus.synced.rawValue
        entity.lastModifiedAt = Date()
        entity.companionsJSON = nil
        try ctx.save()

        await AuthService.shared.signOut()

        XCTAssertNil(entity.companionsJSON)
    }
}
