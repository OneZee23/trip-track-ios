import Foundation

/// Sync status for CoreData entities. Used as Int16 in schema.
/// When server sync is added, SyncService queries by these values.
enum SyncStatus: Int16 {
    /// Created or modified locally, not yet uploaded to server.
    case pendingUpload = 0
    /// Successfully synced with server.
    case synced = 1
    /// Marked for deletion locally. Physical delete after server confirms.
    case pendingDelete = 2
}
