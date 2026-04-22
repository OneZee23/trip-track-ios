import Foundation

enum SyncEnqueuer {
    @MainActor
    static func enqueue(_ op: SyncOperation) {
        guard AuthService.shared.isSignedIn else { return }
        guard SettingsManager.shared.cloudSyncEnabled else { return }
        SyncQueue.shared.enqueue(op)
        // Kick the queue immediately so the operation is pushed to the server as
        // soon as possible. Without this, queued writes would only flush when the
        // 5-minute foreground timer fires (or network is restored) — which meant
        // something like toggling a trip's privacy could take minutes to reach the
        // server. `processQueue()` is idempotent: it early-returns if already running.
        Task { await SyncQueue.shared.processQueue() }
    }
}
