import Foundation
import Combine
import UIKit
import CoreData
import OSLog

private let coordinatorLog = Logger(subsystem: "com.triptrack", category: "sync")

@MainActor
final class SyncCoordinator {
    static let shared = SyncCoordinator()

    private let client = APIClient.shared
    private let queue = SyncQueue.shared
    private let pullApplier = PullApplier()
    private var cancellables = Set<AnyCancellable>()
    private var foregroundTimer: Timer?
    private var isPulling = false

    func start() {
        recoverPendingEntities()

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in Task { await self?.runFullSync() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.stopForegroundTimer() }
            .store(in: &cancellables)

        CacheManager.shared.networkRestored
            .sink { [weak self] in Task { await self?.runFullSync() } }
            .store(in: &cancellables)

        CacheManager.shared.wifiConnected
            .sink { [weak self] in self?.enqueuePendingOriginals() }
            .store(in: &cancellables)

        startForegroundTimer()
    }

    func runFullSync() async {
        guard AuthService.shared.isSignedIn else { return }
        guard SettingsManager.shared.cloudSyncEnabled else { return }
        guard !CacheManager.shared.isOffline else { return }
        guard !isPulling else { return }
        isPulling = true
        defer { isPulling = false }
        await runPull()
        await queue.processQueue()
    }

    private func runPull() async {
        guard let accountId = TokenStore.shared.accountId else {
            coordinatorLog.debug("runPull skipped: no accountId")
            return
        }
        let since = LastSyncedAtStore.get(accountId: accountId)
        let req = SyncPullRequest(lastSyncedAt: since, entityTypes: nil)
        coordinatorLog.debug("pull start since=\(since?.description ?? "nil")")
        do {
            let res: SyncPullResponse = try await client.post(APIEndpoint.syncPull, body: req)
            coordinatorLog.debug("pull got trips=\(res.trips.upserted.count) vehicles=\(res.vehicles.upserted.count) photos=\(res.photos.upserted.count) settings=\(res.settings != nil) serverTime=\(res.serverTime)")
            pullApplier.apply(res)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let serverTime = withFrac.date(from: res.serverTime) ?? plain.date(from: res.serverTime) {
                LastSyncedAtStore.set(serverTime, for: accountId)
                coordinatorLog.debug("lastSyncedAt advanced to \(serverTime)")
            } else {
                coordinatorLog.debug("⚠️ failed to parse serverTime=\(res.serverTime)")
            }
            // Detect server-side data loss: if the server reports fewer
            // non-deleted entities than we have marked `synced` locally, the
            // DB got wiped or rolled back. Re-push the missing ones so the
            // client stays the source of truth — "better than Google Timeline".
            if let counts = res.ownedCounts {
                await reconcileAfterPull(counts: counts)
            }
            NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
        } catch {
            coordinatorLog.debug("pull failed: \(error)")
        }
    }

    // MARK: - Server data-loss reconciliation

    /// Compares server's owned-entity counts against what the client thinks
    /// is synced. On mismatch (server < local) fetches the full manifest of
    /// server-owned UUIDs and marks any local `synced` entity that's missing
    /// as `pendingUpload`, so the queue re-pushes it. Local authoritative.
    private func reconcileAfterPull(counts: SyncPullResponse.OwnedCounts) async {
        let ctx = PersistenceController.shared.container.viewContext
        let localTrips = countSyncedAlive(ctx, entity: TripEntity.fetchRequest())
        let localVehicles = countSyncedAlive(ctx, entity: VehicleEntity.fetchRequest())
        let localPhotos = countSyncedAlive(ctx, entity: TripPhotoEntity.fetchRequest())

        let tripsLost = localTrips > counts.trips
        let vehiclesLost = localVehicles > counts.vehicles
        let photosLost = localPhotos > counts.photos
        guard tripsLost || vehiclesLost || photosLost else { return }

        coordinatorLog.warning(
            "server data-loss suspected — local synced trips=\(localTrips)/srv=\(counts.trips) vehicles=\(localVehicles)/srv=\(counts.vehicles) photos=\(localPhotos)/srv=\(counts.photos); fetching manifest"
        )

        let manifest: SyncManifestResponse
        do {
            manifest = try await client.post(APIEndpoint.syncManifest, body: EmptyRequest())
        } catch {
            coordinatorLog.error("manifest fetch failed: \(error.localizedDescription)")
            return
        }

        // Server's manifest was truncated by its per-type cap — the ID list
        // is incomplete. Reconciliation would false-positive every legit
        // entity beyond the cap as "missing" and re-upload them, inflicting
        // the exact DoS the cap is meant to prevent. Abort safely.
        if manifest.truncated == true {
            coordinatorLog.warning("manifest truncated — skipping reconciliation to avoid false re-upload")
            return
        }

        var repushed = 0
        if tripsLost {
            repushed += reuploadMissing(
                ctx, type: .trip, serverSet: Set(manifest.trips),
                request: TripEntity.fetchRequest() as NSFetchRequest<TripEntity>,
            )
        }
        if vehiclesLost {
            repushed += reuploadMissing(
                ctx, type: .vehicle, serverSet: Set(manifest.vehicles),
                request: VehicleEntity.fetchRequest() as NSFetchRequest<VehicleEntity>,
            )
        }
        if photosLost {
            repushed += reuploadMissing(
                ctx, type: .photo, serverSet: Set(manifest.photos),
                request: TripPhotoEntity.fetchRequest() as NSFetchRequest<TripPhotoEntity>,
            )
        }
        if repushed > 0 {
            do {
                try ctx.save()
                coordinatorLog.warning("reconciliation queued \(repushed) entities for re-upload")
                // Loud warning when the re-upload set is large — helps catch
                // a misbehaving/compromised server that falsely reports
                // `ownedCounts = 0`; the user/developer sees the log and can
                // intervene before egress spikes.
                if repushed >= 100 {
                    coordinatorLog.error("reconciliation LARGE set (\(repushed)) — verify server integrity if unexpected")
                }
            } catch {
                // If save fails, the in-memory flip is lost on relaunch —
                // better to log loudly than silently `try?`-swallow.
                coordinatorLog.error("reconciliation save failed: \(error.localizedDescription)")
            }
        }
    }

    private func countSyncedAlive<T: NSManagedObject>(
        _ ctx: NSManagedObjectContext, entity request: NSFetchRequest<T>,
    ) -> Int {
        request.predicate = NSPredicate(
            format: "syncStatus == %d", SyncStatus.synced.rawValue,
        )
        return (try? ctx.count(for: request)) ?? 0
    }

    /// Flips local `synced` entities not present in `serverSet` to
    /// `pendingUpload` and enqueues an upload op for each. Generic over any
    /// entity that conforms to `SyncStatusHolding` — compile-time access to
    /// `syncStatus` and `id` (replaces brittle KVC setValue calls).
    private func reuploadMissing<T: SyncStatusHolding>(
        _ ctx: NSManagedObjectContext,
        type: SyncOperation.EntityType,
        serverSet: Set<UUID>,
        request: NSFetchRequest<T>,
    ) -> Int {
        request.predicate = NSPredicate(format: "syncStatus == %d", SyncStatus.synced.rawValue)
        let rows = (try? ctx.fetch(request)) ?? []
        var count = 0
        for row in rows {
            guard let id = row.id, !serverSet.contains(id) else { continue }
            row.syncStatus = SyncStatus.pendingUpload.rawValue
            SyncEnqueuer.enqueue(SyncOperation(entityType: type, entityId: id, action: .upload))
            count += 1
        }
        return count
    }

    private func enqueuePendingOriginals() {
        for id in PhotoStorageService.pendingOriginalUploads() {
            SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: id, action: .upload))
        }
    }

    /// After app relaunch, CoreData may contain entities with syncStatus=pendingUpload
    /// that weren't re-enqueued (SyncQueue is in-memory, gets wiped on process kill).
    /// Scan once on start and re-enqueue them.
    private func recoverPendingEntities() {
        let ctx = PersistenceController.shared.container.viewContext
        let pending = SyncStatus.pendingUpload.rawValue
        let pendingDelete = SyncStatus.pendingDelete.rawValue

        let tripReq: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        tripReq.predicate = NSPredicate(format: "syncStatus == %d OR syncStatus == %d", pending, pendingDelete)
        let trips = (try? ctx.fetch(tripReq)) ?? []
        for t in trips {
            guard let id = t.id else { continue }
            let action: SyncOperation.Action = t.syncStatus == pendingDelete ? .delete : .upload
            SyncEnqueuer.enqueue(SyncOperation(entityType: .trip, entityId: id, action: action))
        }

        let vehReq: NSFetchRequest<VehicleEntity> = VehicleEntity.fetchRequest()
        vehReq.predicate = NSPredicate(format: "syncStatus == %d", pending)
        let vehicles = (try? ctx.fetch(vehReq)) ?? []
        for v in vehicles {
            guard let id = v.id else { continue }
            SyncEnqueuer.enqueue(SyncOperation(entityType: .vehicle, entityId: id, action: .upload))
        }

        let photoReq: NSFetchRequest<TripPhotoEntity> = TripPhotoEntity.fetchRequest()
        photoReq.predicate = NSPredicate(format: "syncStatus == %d", pending)
        let photos = (try? ctx.fetch(photoReq)) ?? []
        for p in photos {
            guard let id = p.id else { continue }
            SyncEnqueuer.enqueue(SyncOperation(entityType: .photo, entityId: id, action: .upload))
        }

        let setReq: NSFetchRequest<UserSettingsEntity> = UserSettingsEntity.fetchRequest()
        setReq.predicate = NSPredicate(format: "syncStatus == %d", pending)
        if let s = (try? ctx.fetch(setReq))?.first, let id = s.id {
            SyncEnqueuer.enqueue(SyncOperation(entityType: .settings, entityId: id, action: .upload))
        }

        let total = trips.count + vehicles.count + photos.count
        if total > 0 {
            coordinatorLog.debug("recovered \(total) pending entities after relaunch")
        }
    }

    private func startForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { await SyncCoordinator.shared.runFullSync() }
        }
    }

    private func stopForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }
}
