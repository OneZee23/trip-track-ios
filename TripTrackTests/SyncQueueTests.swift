import XCTest
@testable import TripTrack

/// Mock transport that records executed operations.
private final class MockSyncTransport: SyncTransport {
    var executedOperations: [SyncOperation] = []
    var shouldFail = false
    /// Side-effect hook fired on every execute — lets a test flip external
    /// state (e.g. the auth gate) from inside the drain.
    var onExecute: ((SyncOperation) -> Void)?
    /// Ops handed to the batch fast-path (empty if the batch was never invoked).
    var batchedOps: [SyncOperation] = []
    /// entityIds the batch reports as fully handled — the queue removes exactly
    /// these and lets everything else fall through to `execute()`.
    var batchHandled: Set<UUID> = []

    func execute(_ operation: SyncOperation) async throws {
        defer { onExecute?(operation) }
        if shouldFail {
            throw NSError(domain: "SyncTest", code: 1)
        }
        executedOperations.append(operation)
    }

    @MainActor
    func uploadTripsBatch(_ operations: [SyncOperation], onChunkSynced: @escaping @MainActor (Int) -> Void) async -> Set<UUID> {
        batchedOps = operations
        if !batchHandled.isEmpty { onChunkSynced(batchHandled.count) }
        return batchHandled
    }
}

@MainActor
final class SyncQueueTests: XCTestCase {

    func testEnqueueIncrementsCount() {
        let queue = SyncQueue()
        XCTAssertEqual(queue.pendingCount, 0)

        queue.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))
        XCTAssertEqual(queue.pendingCount, 1)

        queue.enqueue(SyncOperation(entityType: .vehicle, entityId: UUID(), action: .upload))
        XCTAssertEqual(queue.pendingCount, 2)
    }

    func testDeduplication() {
        let queue = SyncQueue()
        let tripId = UUID()

        queue.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .upload))
        queue.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .upload))
        XCTAssertEqual(queue.pendingCount, 1, "Duplicate operations should be ignored")
    }

    func testDifferentActionsNotDeduplicated() {
        let queue = SyncQueue()
        let tripId = UUID()

        queue.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .upload))
        queue.enqueue(SyncOperation(entityType: .trip, entityId: tripId, action: .delete))
        XCTAssertEqual(queue.pendingCount, 2, "Different actions for same entity should both be queued")
    }

    func testClearAll() {
        let queue = SyncQueue()
        queue.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))
        queue.enqueue(SyncOperation(entityType: .photo, entityId: UUID(), action: .upload))

        queue.clearAll()
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testProcessQueueWithoutTransportDoesNothing() async {
        let queue = SyncQueue()
        queue.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))

        await queue.processQueue()
        XCTAssertEqual(queue.pendingCount, 1, "Without transport, queue should not process")
    }

    // MARK: - Batch fast-path (/sync/push)

    /// The batch removes ONLY the entityIds it reports as handled; everything
    /// else falls through to the per-op `execute()` path. This is the data-loss
    /// guard — an op the batch didn't ack must never vanish from the queue.
    func testBatchRemovesOnlyHandledTripOps() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "processQueue bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)
        queue.isAuthorizedToSync = { true }

        let id1 = UUID(), id2 = UUID(), id3 = UUID()
        queue.enqueue(SyncOperation(entityType: .trip, entityId: id1, action: .upload))
        queue.enqueue(SyncOperation(entityType: .trip, entityId: id2, action: .upload))
        queue.enqueue(SyncOperation(entityType: .trip, entityId: id3, action: .upload))
        mock.batchHandled = [id1, id2]  // server acked id1,id2; id3 not acked

        await queue.processQueue()

        XCTAssertEqual(Set(mock.batchedOps.map(\.entityId)), [id1, id2, id3],
                       "All trip .upload ops should be handed to the batch")
        XCTAssertEqual(mock.executedOperations.map(\.entityId), [id3],
                       "Only the un-acked trip falls through to per-op execute()")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    /// A single trip op isn't worth a batch round-trip — it drains per-op.
    func testBatchSkippedForSingleTripOp() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "processQueue bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)
        queue.isAuthorizedToSync = { true }

        let id1 = UUID()
        queue.enqueue(SyncOperation(entityType: .trip, entityId: id1, action: .upload))

        await queue.processQueue()

        XCTAssertTrue(mock.batchedOps.isEmpty, "Batch should be skipped for <2 trip ops")
        XCTAssertEqual(mock.executedOperations.map(\.entityId), [id1])
    }

    /// Only trip `.upload` ops are batched; vehicles/photos/deletes still drain
    /// one-by-one via `execute()`.
    func testBatchLeavesNonTripOpsToPerOp() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "processQueue bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)
        queue.isAuthorizedToSync = { true }

        let t1 = UUID(), t2 = UUID(), v1 = UUID(), p1 = UUID()
        queue.enqueue(SyncOperation(entityType: .trip, entityId: t1, action: .upload))
        queue.enqueue(SyncOperation(entityType: .trip, entityId: t2, action: .upload))
        queue.enqueue(SyncOperation(entityType: .vehicle, entityId: v1, action: .upload))
        queue.enqueue(SyncOperation(entityType: .photo, entityId: p1, action: .upload))
        mock.batchHandled = [t1, t2]

        await queue.processQueue()

        XCTAssertEqual(Set(mock.batchedOps.map(\.entityId)), [t1, t2],
                       "Only trip .upload ops go to the batch")
        XCTAssertEqual(Set(mock.executedOperations.map(\.entityId)), [v1, p1],
                       "Vehicle + photo drain per-op; batched trips do not")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    // MARK: - Auth gating + sign-out races (2026-08-23 incident hardening)

    /// The incident log showed trips/upsert + settings/upsert still firing MID
    /// sign-out: processQueue had no auth gate at all. A drain must not start
    /// when the session is gone.
    func testProcessQueueSkipsWhenNotAuthorized() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "processQueue bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)
        queue.isAuthorizedToSync = { false }

        queue.enqueue(SyncOperation(entityType: .trip, entityId: UUID(), action: .upload))
        await queue.processQueue()

        XCTAssertTrue(mock.executedOperations.isEmpty, "no ops may execute without a session")
        XCTAssertEqual(queue.pendingCount, 1, "ops stay queued for after re-login")
    }

    /// Review finding: the gate must also hold MID-drain. Session expiry is
    /// typically discovered BY the drain (op 1 fails → soft expiry), and the
    /// remaining ops used to fire token-less anyway, burning retry budget.
    func testProcessQueueStopsMidDrainWhenAuthorizationDrops() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "processQueue bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)

        final class GateBox: @unchecked Sendable { var open = true }
        let gate = GateBox()
        queue.isAuthorizedToSync = { gate.open }
        mock.onExecute = { _ in gate.open = false } // op 1 discovers the dead session

        queue.enqueue(SyncOperation(entityType: .vehicle, entityId: UUID(), action: .upload))
        queue.enqueue(SyncOperation(entityType: .vehicle, entityId: UUID(), action: .upload))
        queue.enqueue(SyncOperation(entityType: .vehicle, entityId: UUID(), action: .upload))

        await queue.processQueue()

        XCTAssertEqual(mock.executedOperations.count, 1, "drain must stop after authorization drops")
        XCTAssertEqual(queue.pendingCount, 2, "remaining ops stay pristine for after re-login")
    }

    /// `retryFailed` snapshots eligible ops, sleeps its backoff, then re-appends
    /// them. If sign-out's clearAll lands during that sleep, the snapshot used
    /// to resurrect the wiped ops and POST them with dead tokens.
    func testRetryFailedDoesNotResurrectOpsClearedDuringBackoff() async throws {
        try XCTSkipIf(CacheManager.shared.isOffline, "retryFailed bails when offline")
        let queue = SyncQueue()
        let mock = MockSyncTransport()
        queue.configure(transport: mock)
        queue.isAuthorizedToSync = { true }

        mock.shouldFail = true
        queue.enqueue(SyncOperation(entityType: .settings, entityId: UUID(), action: .upload))
        await queue.processQueue() // parks the op in failedQueue with retryCount=1

        mock.shouldFail = false
        let retryTask = Task { await queue.retryFailed() } // sleeps 2^1 = 2s
        try await Task.sleep(for: .milliseconds(300))
        queue.clearAll() // sign-out lands mid-backoff
        await retryTask.value

        XCTAssertTrue(mock.executedOperations.isEmpty, "cleared ops must not be resurrected")
        XCTAssertEqual(queue.pendingCount, 0)
    }

    func testOperationProperties() {
        let entityId = UUID()
        let op = SyncOperation(entityType: .photo, entityId: entityId, action: .delete)

        XCTAssertEqual(op.entityType, .photo)
        XCTAssertEqual(op.entityId, entityId)
        XCTAssertEqual(op.action, .delete)
        XCTAssertEqual(op.retryCount, 0)
    }
}
