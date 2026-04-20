import Foundation

enum SyncEnqueuer {
    @MainActor
    static func enqueue(_ op: SyncOperation) {
        guard AuthService.shared.isSignedIn else { return }
        guard SettingsManager.shared.cloudSyncEnabled else { return }
        SyncQueue.shared.enqueue(op)
    }
}
