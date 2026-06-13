import Foundation
import Combine

/// Represents a single sync operation in the queue.
struct SyncOperation: Identifiable, Equatable {
    let id: UUID
    let entityType: EntityType
    let entityId: UUID
    let action: Action
    let createdAt: Date
    var retryCount: Int = 0
    /// Last transport error message — populated when an attempt fails so the
    /// sync-status sheet can explain why an operation moved to `failed`.
    var lastError: String?

    enum EntityType: String {
        case trip
        case vehicle
        case photo
        case settings
    }

    enum Action: String {
        case upload
        case update
        case delete
        /// Server-side delete that does NOT touch local storage. Used when a
        /// trip is flipped public→private with Cloud Sync OFF — we want the
        /// public copy gone from the server (privacy-first, no leftovers in
        /// the social feed) while the trip itself stays in the user's local
        /// "Мои" tab. Distinct from `.delete`, which hard-removes locally.
        case unpublish
    }

    init(entityType: EntityType, entityId: UUID, action: Action) {
        self.id = UUID()
        self.entityType = entityType
        self.entityId = entityId
        self.action = action
        self.createdAt = Date()
    }
}

/// Transport protocol — implemented by the actual API client when server is ready.
protocol SyncTransport {
    func execute(_ operation: SyncOperation) async throws
    /// Batch-uploads trip `.upload` ops via `/sync/push`, collapsing N serial
    /// per-trip POSTs into a few chunked requests. Returns the entityIds it
    /// FULLY handled (synced, or conflict-resolved) — the queue removes only
    /// those; anything not returned (privacy-skip, chunk failure, unresolved)
    /// stays queued and is drained by the proven per-op `execute()` path. This
    /// makes the batch a pure optimization that can never lose an op.
    ///
    /// `onChunkSynced` is invoked with the count handled as each chunk lands, so
    /// the progress UI advances during the batch instead of jumping 0→N at the end.
    /// `@MainActor` so the callback runs synchronously on the main actor — the
    /// caller mutates `@Published` progress in it, no fire-and-forget hop needed.
    @MainActor
    func uploadTripsBatch(_ operations: [SyncOperation], onChunkSynced: @escaping @MainActor (Int) -> Void) async -> Set<UUID>
}

extension SyncTransport {
    // Default: batch nothing → everything falls through to per-op execute().
    @MainActor
    func uploadTripsBatch(_ operations: [SyncOperation], onChunkSynced: @escaping @MainActor (Int) -> Void) async -> Set<UUID> { [] }
}

/// Manages a queue of pending sync operations with retry and prioritization.
/// Integrates with CacheManager.networkRestored to auto-process when online.
@MainActor
final class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    @Published private(set) var batchTotal = 0     // total ops in the current batch
    @Published private(set) var batchProcessed = 0 // ops completed (success or failed) in current batch
    /// Currently executing operation, when `isSyncing` is true. Lets the
    /// status sheet show "Now: trip upload" instead of just "Syncing…".
    @Published private(set) var currentOperation: SyncOperation?
    /// Snapshot mirrors of `queue` and `failedQueue` for SwiftUI consumers.
    /// Kept separate from the internal mutating arrays so we don't have to
    /// publish each tiny intermediate state during the inner sync loop;
    /// `republishSnapshots()` updates them at well-defined points.
    @Published private(set) var pending: [SyncOperation] = []
    @Published private(set) var failed: [SyncOperation] = []

    private var queue: [SyncOperation] = []
    private var failedQueue: [SyncOperation] = []
    private var cancellables = Set<AnyCancellable>()
    private var transport: SyncTransport?
    /// Auto-retry cap. After this many failures, an op stays in `failedQueue`
    /// but `retryFailed` (the auto-retry path) skips it — only `retryFailedNow`
    /// (user-initiated) can revive it. Previously ops were *silently dropped*
    /// after `maxRetries`, causing data loss when the server had a persistent
    /// problem on a specific record.
    private let maxRetries = 5

    /// Priority order: metadata first, then photos (heavier).
    private let entityPriority: [SyncOperation.EntityType] = [
        .settings, .vehicle, .trip, .photo
    ]

    init() {
        CacheManager.shared.networkRestored
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.processQueue()
                }
            }
            .store(in: &cancellables)
    }

    /// Set the transport when server is configured.
    func configure(transport: SyncTransport) {
        self.transport = transport
    }

    func enqueue(_ operation: SyncOperation) {
        let isDuplicate = queue.contains {
            $0.entityId == operation.entityId &&
            $0.entityType == operation.entityType &&
            $0.action == operation.action
        }
        guard !isDuplicate else { return }
        queue.append(operation)
        updatePendingCount()
        republishSnapshots()
    }

    /// Cancels every pending op for a given entity. Called when an entity
    /// is deleted before its other queued ops (upload/update) get a chance
    /// to fire — without this, a junk trip that fails the post-stop filter
    /// could be POSTed to the server moments before its DELETE arrives.
    /// Order matters because the queue is FIFO — by purging on delete-
    /// enqueue we guarantee the server never sees the doomed trip.
    func cancelOperations(for entityId: UUID, entityType: SyncOperation.EntityType) {
        let beforeCount = queue.count
        queue.removeAll { $0.entityId == entityId && $0.entityType == entityType }
        failedQueue.removeAll { $0.entityId == entityId && $0.entityType == entityType }
        if queue.count != beforeCount {
            updatePendingCount()
            republishSnapshots()
        }
    }

    func processQueue() async {
        guard !isSyncing else { return }
        guard let activeTransport = transport else { return }
        guard !CacheManager.shared.isOffline else { return }
        guard !queue.isEmpty else { return }

        isSyncing = true
        batchTotal = queue.count
        batchProcessed = 0
        defer {
            isSyncing = false
            batchTotal = 0
            batchProcessed = 0
            currentOperation = nil
            updatePendingCount()
            republishSnapshots()
        }

        queue.sort { lhs, rhs in
            let lhsPriority = entityPriority.firstIndex(of: lhs.entityType) ?? Int.max
            let rhsPriority = entityPriority.firstIndex(of: rhs.entityType) ?? Int.max
            return lhsPriority < rhsPriority
        }
        republishSnapshots()

        // Batch fast-path: collapse trip `.upload` ops into a few `/sync/push`
        // requests instead of N serial per-trip POSTs (the source of the
        // one-by-one drain + per-op main-thread churn). The transport returns
        // the entityIds it fully handled; we remove ONLY those. Anything it
        // didn't ack — privacy-skip, conflict it couldn't resolve, or a failed
        // chunk — stays in `queue` and the per-op loop below drains it the
        // proven way, so the batch can never drop an op. Skip for ≤1 trip.
        let tripUploadOps = queue.filter { $0.entityType == .trip && $0.action == .upload }
        if tripUploadOps.count >= 2 {
            // Advance the progress counter as each chunk lands (the batch is one
            // long await otherwise, so the UI would sit at 0/N then jump). The
            // callback is @MainActor + called synchronously, so it mutates the
            // @Published progress directly — no fire-and-forget Task that could
            // outlive the drain.
            let handled = await activeTransport.uploadTripsBatch(tripUploadOps) { [weak self] syncedCount in
                guard let self else { return }
                self.batchProcessed += syncedCount
                self.updatePendingCount()
                self.republishSnapshots()
            }
            if !handled.isEmpty {
                queue.removeAll {
                    $0.entityType == .trip && $0.action == .upload && handled.contains($0.entityId)
                }
                updatePendingCount()
                republishSnapshots()
            }
        }

        while !queue.isEmpty {
            guard !CacheManager.shared.isOffline else { break }

            var operation = queue.removeFirst()
            currentOperation = operation
            updatePendingCount()
            republishSnapshots()

            do {
                try await activeTransport.execute(operation)
            } catch {
                operation.retryCount += 1
                operation.lastError = (error as? LocalizedError)?.errorDescription
                    ?? String(describing: error)
                // Always park in failedQueue. The cap on auto-retry lives in
                // `retryFailed` (it skips ops with retryCount >= maxRetries);
                // the op itself stays visible to the user and can be revived
                // via the manual "Retry now" button. Silent drop on retryCount=3
                // used to lose data permanently on persistent server errors.
                failedQueue.append(operation)
                #if DEBUG
                print("SyncQueue: operation \(operation.entityType.rawValue)/\(operation.action.rawValue) failed (attempt \(operation.retryCount)): \(error)")
                #endif
            }
            batchProcessed += 1
        }
    }

    /// Retry failed operations with batch-level exponential backoff.
    /// Skips ops that have hit the auto-retry cap — those stay in `failedQueue`
    /// awaiting manual retry. Without this gate, a persistently-failing op
    /// would re-enter `queue` on every foreground tick, hammering the server.
    func retryFailed() async {
        guard !failedQueue.isEmpty else { return }
        guard !CacheManager.shared.isOffline else { return }

        let eligible = failedQueue.filter { $0.retryCount < maxRetries }
        guard !eligible.isEmpty else { return }

        let maxRetryCount = eligible.map(\.retryCount).max() ?? 0
        let batchDelay = pow(2.0, Double(maxRetryCount))
        try? await Task.sleep(for: .seconds(batchDelay))

        failedQueue.removeAll { op in eligible.contains(where: { $0.id == op.id }) }
        queue.append(contentsOf: eligible)
        republishSnapshots()

        await processQueue()
    }

    /// User-initiated retry of failed ops (no backoff sleep) — wired to the
    /// "Retry now" button in the sync-status sheet. Resets `lastError` so the
    /// UI doesn't keep showing the previous failure reason while we retry.
    func retryFailedNow() async {
        guard !failedQueue.isEmpty else { return }
        let toRetry = failedQueue.map { op -> SyncOperation in
            var clean = op
            clean.lastError = nil
            return clean
        }
        failedQueue.removeAll()
        queue.append(contentsOf: toRetry)
        republishSnapshots()
        await processQueue()
    }

    /// Clear all queued operations (e.g., on logout).
    func clearAll() {
        queue.removeAll()
        failedQueue.removeAll()
        updatePendingCount()
        republishSnapshots()
    }

    private func updatePendingCount() {
        pendingCount = queue.count + failedQueue.count
    }

    private func republishSnapshots() {
        pending = queue
        failed = failedQueue
    }
}
