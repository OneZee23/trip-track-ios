import Foundation
import CoreData

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

/// Shared shape for CoreData entities that carry a `syncStatus` column —
/// lets generic sync machinery flip status at compile-time safety instead of
/// KVC string keys that break silently on rename. All four of `TripEntity`,
/// `VehicleEntity`, `TripPhotoEntity`, `UserSettingsEntity` declare
/// `@NSManaged var syncStatus: Int16` so conformance is free.
protocol SyncStatusHolding: NSManagedObject {
    var syncStatus: Int16 { get set }
    var id: UUID? { get }
}

extension TripEntity: SyncStatusHolding {}
extension VehicleEntity: SyncStatusHolding {}
extension TripPhotoEntity: SyncStatusHolding {}
