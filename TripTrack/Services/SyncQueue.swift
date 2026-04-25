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
    private let maxRetries = 3

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
                if operation.retryCount < maxRetries {
                    failedQueue.append(operation)
                }
                #if DEBUG
                print("SyncQueue: operation \(operation.entityType.rawValue)/\(operation.action.rawValue) failed (attempt \(operation.retryCount)): \(error)")
                #endif
            }
            batchProcessed += 1
        }
    }

    /// Retry failed operations with batch-level exponential backoff.
    func retryFailed() async {
        guard !failedQueue.isEmpty else { return }
        guard !CacheManager.shared.isOffline else { return }

        let maxRetryCount = failedQueue.map(\.retryCount).max() ?? 0
        let batchDelay = pow(2.0, Double(maxRetryCount))
        try? await Task.sleep(for: .seconds(batchDelay))

        let toRetry = failedQueue
        failedQueue.removeAll()
        queue.append(contentsOf: toRetry)
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
