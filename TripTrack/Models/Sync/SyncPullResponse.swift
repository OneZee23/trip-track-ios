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

    let trips: TripsSection
    let vehicles: VehiclesSection
    let photos: PhotosSection
    let settings: SettingsSyncPayload?
    let serverTime: String
}
