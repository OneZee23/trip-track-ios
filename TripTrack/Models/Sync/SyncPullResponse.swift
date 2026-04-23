import Foundation

struct SyncPullResponse: Codable {
    struct TripsSection: Codable {
        let upserted: [TripSyncPayload]
        let deleted: [UUID]
    }
    struct VehiclesSection: Codable {
        let upserted: [VehicleSyncPayload]
        let deleted: [UUID]
    }
    struct PhotosSection: Codable {
        let upserted: [PhotoSyncPayload]
        let deleted: [UUID]
    }

    /// Count of non-deleted entities the server currently holds for this
    /// account. Client compares against local `synced` count to detect
    /// server-side data loss and trigger reconciliation via `/sync/manifest`.
    /// Optional for backwards compatibility with older backends.
    struct OwnedCounts: Codable {
        let trips: Int
        let vehicles: Int
        let photos: Int
    }

    let trips: TripsSection
    let vehicles: VehiclesSection
    let photos: PhotosSection
    let settings: SettingsSyncPayload?
    let serverTime: String
    let ownedCounts: OwnedCounts?
}

/// Full list of entity UUIDs the server currently owns. Fetched only when
/// `ownedCounts` disagrees with local state — used to identify specifically
/// which local-synced entities the server has lost so they can be re-uploaded.
///
/// `truncated` is set when the server's per-type cap was hit — the ID list
/// is incomplete and MUST NOT drive reconciliation, otherwise client would
/// flag legit server-owned entities as "missing" and re-upload them.
struct SyncManifestResponse: Codable {
    let trips: [UUID]
    let vehicles: [UUID]
    let photos: [UUID]
    let truncated: Bool?
}
