import XCTest
@testable import TripTrack

/// Mock transport that records executed operations.
private final class MockSyncTransport: SyncTransport {
    var executedOperations: [SyncOperation] = []
    var shouldFail = false
    /// Ops handed to the batch fast-path (empty if the batch was never invoked).
    var batchedOps: [SyncOperation] = []
    /// entityIds the batch reports as fully handled — the queue removes exactly
    /// these and lets everything else fall through to `execute()`.
    var batchHandled: Set<UUID> = []

    func execute(_ operation: SyncOperation) async throws {
        if shouldFail {
            throw NSError(domain: "SyncTest", code: 1)
        }
        executedOperations.append(operation)
    }

    func uploadTripsBatch(_ operations: [SyncOperation]) async -> Set<UUID> {
        batchedOps = operations
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

    func testOperationProperties() {
        let entityId = UUID()
        let op = SyncOperation(entityType: .photo, entityId: entityId, action: .delete)

        XCTAssertEqual(op.entityType, .photo)
        XCTAssertEqual(op.entityId, entityId)
        XCTAssertEqual(op.action, .delete)
        XCTAssertEqual(op.retryCount, 0)
    }
}
