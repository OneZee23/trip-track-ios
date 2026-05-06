import Foundation
import CoreData

enum SyncEnqueuer {
    @MainActor
    static func enqueue(_ op: SyncOperation) {
        guard AuthService.shared.isSignedIn else { return }
        guard shouldEnqueue(op) else { return }
        SyncQueue.shared.enqueue(op)
        // Kick the queue immediately so the operation is pushed to the server as
        // soon as possible. Without this, queued writes would only flush when the
        // 5-minute foreground timer fires (or network is restored) — which meant
        // something like toggling a trip's privacy could take minutes to reach the
        // server. `processQueue()` is idempotent: it early-returns if already running.
        Task { await SyncQueue.shared.processQueue() }
    }

    /// Privacy-first per-op gate. With Cloud Sync ON the user has opted into
    /// full mirror — anything goes. With Cloud Sync OFF only **explicitly
    /// public** content is allowed to leave the device: a trip the user has
    /// flipped to public, a photo whose parent trip is public, and the
    /// server-delete that follows un-publishing. Settings and vehicles are
    /// never publishable on their own — they're personal metadata.
    /// Fail-closed: if we can't resolve the entity, we deny.
    @MainActor
    private static func shouldEnqueue(_ op: SyncOperation) -> Bool {
        if SettingsManager.shared.cloudSyncEnabled { return true }
        switch op.entityType {
        case .trip:
            // .unpublish always passes — it's the server-delete half of a
            // private-flip and must complete or the trip stays public.
            if op.action == .unpublish { return true }
            // .delete passes only if we still have an entity AND it's marked
            // pendingDelete — that's an explicit user-initiated delete of a
            // (presumably public) trip. Otherwise (e.g. junk auto-delete of
            // a never-published trip) skip.
            if op.action == .delete {
                guard let entity = fetchTripEntity(id: op.entityId) else { return false }
                return entity.serverCreatedAt != nil
            }
            // .upload / .update pass only when the trip itself is public.
            guard let entity = fetchTripEntity(id: op.entityId) else { return false }
            return entity.isPrivate == false
        case .photo:
            // Photos ride along with the parent trip's privacy. .delete of a
            // photo passes only if it actually exists on server (remoteURL).
            if op.action == .delete {
                guard let entity = fetchPhotoEntity(id: op.entityId) else { return false }
                return entity.remoteURL != nil
            }
            guard let entity = fetchPhotoEntity(id: op.entityId),
                  let trip = entity.trip else { return false }
            return trip.isPrivate == false
        case .vehicle, .settings:
            // Personal metadata — never leaves device without full sync ON.
            return false
        }
    }

    @MainActor
    private static func fetchTripEntity(id: UUID) -> TripEntity? {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? ctx.fetch(req).first
    }

    @MainActor
    private static func fetchPhotoEntity(id: UUID) -> TripPhotoEntity? {
        let ctx = PersistenceController.shared.container.viewContext
        let req: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        req.fetchLimit = 1
        return try? ctx.fetch(req).first
    }
}
