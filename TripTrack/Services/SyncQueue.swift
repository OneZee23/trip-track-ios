import Foundation
import Combine

/// Represents a single sync operation in the queue.
struct SyncOperation: Identifiable {
    let id: UUID
    let entityType: EntityType
    let entityId: UUID
    let action: Action
    let createdAt: Date
    var retryCount: Int = 0

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
    }

    func processQueue() async {
        guard !isSyncing else { return }
        guard let activeTransport = transport else { return }
        guard !CacheManager.shared.isOffline else { return }
        guard !queue.isEmpty else { return }

        isSyncing = true
        defer {
            isSyncing = false
            updatePendingCount()
        }

        queue.sort { lhs, rhs in
            let lhsPriority = entityPriority.firstIndex(of: lhs.entityType) ?? Int.max
            let rhsPriority = entityPriority.firstIndex(of: rhs.entityType) ?? Int.max
            return lhsPriority < rhsPriority
        }

        while !queue.isEmpty {
            guard !CacheManager.shared.isOffline else { break }

            var operation = queue.removeFirst()

            do {
                try await activeTransport.execute(operation)
            } catch {
                operation.retryCount += 1
                if operation.retryCount < maxRetries {
                    failedQueue.append(operation)
                }
                #if DEBUG
                print("SyncQueue: operation \(operation.entityType.rawValue)/\(operation.action.rawValue) failed (attempt \(operation.retryCount)): \(error)")
                #endif
            }
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

        await processQueue()
    }

    /// Clear all queued operations (e.g., on logout).
    func clearAll() {
        queue.removeAll()
        failedQueue.removeAll()
        updatePendingCount()
    }

    private func updatePendingCount() {
        pendingCount = queue.count + failedQueue.count
    }
}
