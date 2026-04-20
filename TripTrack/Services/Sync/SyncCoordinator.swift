import Foundation
import Combine
import UIKit

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
