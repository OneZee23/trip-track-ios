import XCTest
@testable import TripTrack

/// Mock transport that records executed operations.
private final class MockSyncTransport: SyncTransport {
    var executedOperations: [SyncOperation] = []
    var shouldFail = false

    func execute(_ operation: SyncOperation) async throws {
        if shouldFail {
            throw NSError(domain: "SyncTest", code: 1)
        }
        executedOperations.append(operation)
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

    func testOperationProperties() {
        let entityId = UUID()
        let op = SyncOperation(entityType: .photo, entityId: entityId, action: .delete)

        XCTAssertEqual(op.entityType, .photo)
        XCTAssertEqual(op.entityId, entityId)
        XCTAssertEqual(op.action, .delete)
        XCTAssertEqual(op.retryCount, 0)
    }
}
