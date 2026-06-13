import Foundation

/// Batch upload to `POST /sync/push`. Collapses what used to be N serial
/// `/trips/upsert` round-trips (one per trip) into one request. Only trips are
/// batched here — photos (R2 blobs) and deletes stay on the per-op path.
struct SyncPushRequest: Encodable {
    let trips: [TripSyncPayload]
}

/// Response from `POST /sync/push`. We only consume `trips` (the batch we sent);
/// the server also returns vehicles/deletions/settings/conflicts/serverTime,
/// which are decoded leniently (all optional) and ignored for the trips-only batch.
struct SyncPushResponse: Decodable {
    struct TripResult: Decodable {
        let id: UUID
        let conflictVersion: Int
        /// "created" | "updated" | "conflict"
        let status: String
        /// Present for created/updated trips so the client can
        /// `markSynced(serverCreatedAt:)` exactly like the per-trip path.
        let serverCreatedAt: Date?
    }

    let trips: [TripResult]?
}
