import Foundation
import Combine
import UIKit
import CoreData

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
        // Recovery: re-enqueue any local entities marked pendingUpload but not in the in-memory queue
        // (happens after app kill mid-sync — queue state is lost, but syncStatus on CoreData persists)
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
            print("[SyncCoordinator] runPull skipped: no accountId")
            return
        }
        let since = LastSyncedAtStore.get(accountId: accountId)
        let req = SyncPullRequest(lastSyncedAt: since, entityTypes: nil)
        print("[SyncCoordinator] pull start since=\(since?.description ?? "nil")")
        do {
            let res: SyncPullResponse = try await client.post(APIEndpoint.syncPull, body: req)
            print("[SyncCoordinator] pull got trips=\(res.trips.upserted.count) vehicles=\(res.vehicles.upserted.count) photos=\(res.photos.upserted.count) settings=\(res.settings != nil) serverTime=\(res.serverTime)")
            pullApplier.apply(res)
            let withFrac = ISO8601DateFormatter()
            withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let serverTime = withFrac.date(from: res.serverTime) ?? plain.date(from: res.serverTime) {
                LastSyncedAtStore.set(serverTime, for: accountId)
                print("[SyncCoordinator] lastSyncedAt advanced to \(serverTime)")
            } else {
                print("[SyncCoordinator] ⚠️ failed to parse serverTime=\(res.serverTime)")
            }
            // Notify UI that remote data was applied
            NotificationCenter.default.post(name: .syncPullCompleted, object: nil)
        } catch {
            print("[SyncCoordinator] pull failed: \(error)")
        }
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
            print("[SyncCoordinator] recovered \(total) pending entities after relaunch")
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
