import XCTest
import CoreData
@testable import TripTrack

/// End-to-end coverage of the privacy-first sync state machine. Targets the
/// nasty/murky edge cases caught (and fixed) across audit rounds 1–4:
///
/// * trip lifecycle (private default → public → private)
/// * rapid public↔private toggle race
/// * delete short-circuit for never-uploaded trips
/// * markUnpublished not clobbering a re-flip back to public
/// * migrateAllTripsToPrivate semantics
/// * updateTitle/updateNotes not stuck pendingUpload for private+OFF
@MainActor
final class PrivacyFlowE2ETests: XCTestCase {
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
        SettingsManager.shared.cloudSyncEnabled = false
        super.tearDown()
    }

    // MARK: - Helpers

    /// Inserts a TripEntity with the given state, bypassing TripManager's
    /// production side effects. Returns its UUID.
    @discardableResult
    private func insertTrip(
        isPrivate: Bool = true,
        serverCreatedAt: Date? = nil,
        syncStatus: SyncStatus = .synced,
        conflictVersion: Int32 = 0
    ) -> UUID {
        let ctx = pc.container.viewContext
        let entity = TripEntity(context: ctx)
        let id = UUID()
        entity.id = id
        entity.userId = SettingsManager.shared.localUserId
        entity.startDate = Date()
        entity.endDate = Date().addingTimeInterval(600)
        entity.isPrivate = isPrivate
        entity.serverCreatedAt = serverCreatedAt
        entity.syncStatus = syncStatus.rawValue
        entity.conflictVersion = conflictVersion
        entity.lastModifiedAt = Date()
        try? ctx.save()
        return id
    }

    private func entity(for id: UUID) -> TripEntity? {
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? pc.container.viewContext.fetch(req).first
    }

    // MARK: - updatePrivacy state machine

    func testPrivateNeverUploadedToPublicAtSyncOff_marksPendingUpload() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(isPrivate: true, serverCreatedAt: nil)

        repo.updatePrivacy(for: id, isPrivate: false)

        let e = entity(for: id)
        XCTAssertNotNil(e)
        XCTAssertFalse(e!.isPrivate, "trip should be public after flip")
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "newly-public trip needs upload")
        XCTAssertNil(e!.serverCreatedAt, "no server copy yet")
    }

    func testPublicSyncedToPrivateAtSyncOff_marksPendingUploadForUnpublishOp() {
        // Simulating a trip that previously made it to the server (Cloud Sync
        // ON era). User is now at OFF and toggles private. We expect the
        // entity to enter `pendingUpload` so a concurrent /sync/pull's
        // skip-guard refuses to overwrite local privacy.
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: Date(),
            syncStatus: .synced, conflictVersion: 3
        )

        repo.updatePrivacy(for: id, isPrivate: true)

        let e = entity(for: id)
        XCTAssertTrue(e!.isPrivate)
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "must be pendingUpload while .unpublish op is in flight")
        XCTAssertNotNil(e!.serverCreatedAt, "still on server until .unpublish lands")
    }

    func testPublicSyncedToPrivateAtSyncOn_marksPendingUploadForUpdateOp() {
        SettingsManager.shared.cloudSyncEnabled = true
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: Date(),
            syncStatus: .synced, conflictVersion: 3
        )

        repo.updatePrivacy(for: id, isPrivate: true)

        let e = entity(for: id)
        XCTAssertTrue(e!.isPrivate)
        // Cloud Sync ON path keeps the trip on server with is_private=true.
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingUpload.rawValue)
        XCTAssertNotNil(e!.serverCreatedAt, "trip stays on server (just private flag flipped)")
    }

    func testPrivateNeverUploadedToPrivate_isNoOp() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(isPrivate: true, serverCreatedAt: nil, syncStatus: .synced)

        repo.updatePrivacy(for: id, isPrivate: true)

        let e = entity(for: id)
        XCTAssertTrue(e!.isPrivate)
        XCTAssertEqual(e!.syncStatus, SyncStatus.synced.rawValue,
                       "no change should not flip syncStatus")
    }

    // MARK: - deleteTrip short-circuit (Round 1 fix)

    func testDeleteNeverUploadedTrip_hardDeletesImmediately() {
        // The bug we fixed: a never-uploaded private trip gets `pendingDelete`,
        // SyncEnqueuer privacy gate denies the .delete enqueue (no
        // serverCreatedAt → nothing to delete remotely), and the entity sits
        // in `pendingDelete` forever — ghost in the UI.
        let id = insertTrip(isPrivate: true, serverCreatedAt: nil)

        repo.deleteTrip(id: id)

        XCTAssertNil(entity(for: id),
                     "never-uploaded trip should be hard-deleted, not soft")
    }

    func testDeleteUploadedTrip_softDeletesAndQueuesNetworkDelete() {
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: Date(), syncStatus: .synced
        )

        repo.deleteTrip(id: id)

        let e = entity(for: id)
        XCTAssertNotNil(e, "uploaded trip should soft-delete (entity remains)")
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingDelete.rawValue)
    }

    // MARK: - markUnpublished concurrent re-flip race (Round 3 R10)

    func testMarkUnpublished_doesNotClobberIsPrivateIfUserReFlipped() {
        // Scenario: user flipped public→private (queued .unpublish), then
        // before .unpublish's API call returned, flipped back to public.
        // markUnpublished runs after the server-delete completes — it MUST
        // NOT force isPrivate=true (would clobber the user's newer choice).
        let id = insertTrip(
            isPrivate: false, // user's latest choice: public
            serverCreatedAt: Date(),
            syncStatus: .pendingUpload,
            conflictVersion: 5
        )

        repo.markUnpublished(tripId: id)

        let e = entity(for: id)
        XCTAssertFalse(e!.isPrivate,
                       "user's re-flip to public must survive the .unpublish ack")
        XCTAssertNil(e!.serverCreatedAt, "server bookkeeping cleared")
        XCTAssertEqual(e!.conflictVersion, 0)
        // syncStatus stays .pendingUpload because the trip is still public
        // and needs to re-upload.
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "re-flipped public trip stays pending for .upload")
    }

    func testMarkUnpublished_normalCase_resetsToSynced() {
        let id = insertTrip(
            isPrivate: true, serverCreatedAt: Date(),
            syncStatus: .pendingUpload, conflictVersion: 3
        )

        repo.markUnpublished(tripId: id)

        let e = entity(for: id)
        XCTAssertTrue(e!.isPrivate)
        XCTAssertNil(e!.serverCreatedAt)
        XCTAssertEqual(e!.conflictVersion, 0)
        XCTAssertEqual(e!.syncStatus, SyncStatus.synced.rawValue,
                       "private + no server copy + nothing pending = synced")
    }

    // MARK: - migrateAllTripsToPrivate (Round 1 C1)

    func testMigration_flipsPublicTripsToPrivateAndReturnsServerSideIds() {
        let publicSyncedId = insertTrip(
            isPrivate: false, serverCreatedAt: Date(), syncStatus: .synced
        )
        let publicLocalId = insertTrip(
            isPrivate: false, serverCreatedAt: nil, syncStatus: .pendingUpload
        )
        let alreadyPrivateId = insertTrip(
            isPrivate: true, serverCreatedAt: nil, syncStatus: .synced
        )

        let serverSideIds = repo.migrateAllTripsToPrivate()

        XCTAssertEqual(Set(serverSideIds), [publicSyncedId],
                       "only trips with serverCreatedAt should be returned for unpublish")

        XCTAssertTrue(entity(for: publicSyncedId)!.isPrivate)
        XCTAssertTrue(entity(for: publicLocalId)!.isPrivate)
        XCTAssertTrue(entity(for: alreadyPrivateId)!.isPrivate, "already-private untouched")
    }

    func testMigration_doesNotFlipSyncStatusToPendingUpload() {
        // Earlier version of the migration set syncStatus = pendingUpload for
        // every flipped trip. With the privacy-first gate, that left private
        // trips at OFF stuck pending forever (gate denies enqueue). The
        // migration should leave syncStatus alone.
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: nil, syncStatus: .synced
        )

        _ = repo.migrateAllTripsToPrivate()

        XCTAssertEqual(entity(for: id)!.syncStatus, SyncStatus.synced.rawValue,
                       "syncStatus must NOT be flipped to pendingUpload by migration")
    }

    // MARK: - updateTitle / updateNotes don't strand private trips

    func testUpdateTitleOnPrivateTripAtSyncOff_doesNotFlipSyncStatus() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(
            isPrivate: true, serverCreatedAt: nil, syncStatus: .synced
        )

        repo.updateTitle(for: id, title: "New Title")

        let e = entity(for: id)
        XCTAssertEqual(e!.title, "New Title")
        XCTAssertEqual(e!.syncStatus, SyncStatus.synced.rawValue,
                       "private+OFF: gate denies enqueue → don't strand pending")
    }

    func testUpdateTitleOnPublicTripAtSyncOff_flipsSyncStatus() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: Date(), syncStatus: .synced
        )

        repo.updateTitle(for: id, title: "Public Title")

        XCTAssertEqual(entity(for: id)!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "public trip needs to push update even at OFF (gate allows)")
    }

    func testUpdateTitleOnPrivateTripAtSyncOn_flipsSyncStatus() {
        SettingsManager.shared.cloudSyncEnabled = true
        let id = insertTrip(
            isPrivate: true, serverCreatedAt: Date(), syncStatus: .synced
        )

        repo.updateTitle(for: id, title: "Synced Private")

        XCTAssertEqual(entity(for: id)!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       "Cloud Sync ON: every edit pushes")
    }

    func testUpdateNotesOnPrivateTripAtSyncOff_doesNotFlipSyncStatus() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(
            isPrivate: true, serverCreatedAt: nil, syncStatus: .synced
        )

        repo.updateNotes(for: id, notes: "Notes content")

        XCTAssertEqual(entity(for: id)!.tripDescription, "Notes content")
        XCTAssertEqual(entity(for: id)!.syncStatus, SyncStatus.synced.rawValue)
    }

    // MARK: - Sequential public↔private↔public via repo

    func testRapidPublicPrivatePublic_endsInExpectedState() {
        SettingsManager.shared.cloudSyncEnabled = false
        let id = insertTrip(
            isPrivate: false, serverCreatedAt: Date(),
            syncStatus: .synced, conflictVersion: 2
        )

        // public → private (.unpublish queued, syncStatus pendingUpload)
        repo.updatePrivacy(for: id, isPrivate: true)
        XCTAssertTrue(entity(for: id)!.isPrivate)
        XCTAssertEqual(entity(for: id)!.syncStatus, SyncStatus.pendingUpload.rawValue)

        // Simulate user flipping back to public BEFORE .unpublish drained.
        // serverCreatedAt is still set locally because markUnpublished hasn't
        // run yet — so this re-enters the wasSynced=true branch.
        repo.updatePrivacy(for: id, isPrivate: false)

        let e = entity(for: id)
        XCTAssertFalse(e!.isPrivate, "final state: public again")
        XCTAssertEqual(e!.syncStatus, SyncStatus.pendingUpload.rawValue,
                       ".update or .upload op queued")

        // Now markUnpublished fires (the original .unpublish ack) — must
        // NOT clobber the user's re-flip.
        repo.markUnpublished(tripId: id)

        let after = entity(for: id)
        XCTAssertFalse(after!.isPrivate,
                       "isPrivate stays false because user re-toggled to public")
        XCTAssertNil(after!.serverCreatedAt,
                     "server-side bookkeeping cleared (server-delete did happen)")
    }

    // MARK: - shouldFlipPendingUpload truth table

    func testTruthTableForUpdateMethods() {
        // Pulled from the actual implementation; documents intent:
        //   public  + ON  → pending  (full mirror)
        //   public  + OFF → pending  (publishing edit needs to land)
        //   private + ON  → pending  (full mirror)
        //   private + OFF → keep .synced (gate denies, no point queuing)
        let cases: [(Bool, Bool, SyncStatus)] = [
            (false, true,  .pendingUpload),
            (false, false, .pendingUpload),
            (true,  true,  .pendingUpload),
            (true,  false, .synced),
        ]
        for (isPrivate, cloudOn, expected) in cases {
            SettingsManager.shared.cloudSyncEnabled = cloudOn
            let id = insertTrip(
                isPrivate: isPrivate,
                serverCreatedAt: isPrivate ? nil : Date(),
                syncStatus: .synced
            )
            repo.updateTitle(for: id, title: "x")
            XCTAssertEqual(
                entity(for: id)!.syncStatus, expected.rawValue,
                "isPrivate=\(isPrivate) cloudOn=\(cloudOn) → expected \(expected)"
            )
        }
    }
}
