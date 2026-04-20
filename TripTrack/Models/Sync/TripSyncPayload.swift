import Foundation

struct TripPhotoMetadataPayload: Codable {
    let id: UUID
    let filename: String
    let caption: String?
    let timestamp: Date
    let sortOrder: Int
}

struct TripSyncPayload: Codable {
    let id: UUID
    let title: String?
    let description: String?
    let startDate: Date
    let endDate: Date?
    let distance: Double
    let maxSpeed: Double
    let averageSpeed: Double
    let fuelUsed: Double
    let elevation: Double
    let region: String?
    let isPrivate: Bool
    let vehicleId: UUID?
    let fuelCurrency: String?
    let previewPolyline: String?
    let badgesJson: String?
    let xpEarned: Int?
    let conflictVersion: Int
    let lastModifiedAt: Date
    let trackPoints: [TrackPointPayload]
    let photos: [TripPhotoMetadataPayload]?
}

extension TripSyncPayload {
    init(trip: Trip, entity: TripEntity) {
        self.id = trip.id
        self.title = trip.title
        self.description = trip.tripDescription
        self.startDate = trip.startDate
        self.endDate = trip.endDate
        self.distance = trip.distance
        self.maxSpeed = trip.maxSpeed
        self.averageSpeed = trip.averageSpeed
        self.fuelUsed = trip.fuelUsed
        self.elevation = trip.elevation
        self.region = trip.region
        self.isPrivate = trip.isPrivate
        self.vehicleId = trip.vehicleId
        self.fuelCurrency = trip.fuelCurrency
        self.previewPolyline = trip.previewPolyline?.base64EncodedString()
        self.badgesJson = entity.badgesJSON
        self.xpEarned = Int(entity.xpEarned)
        self.conflictVersion = Int(entity.conflictVersion)
        self.lastModifiedAt = entity.lastModifiedAt ?? Date()
        self.trackPoints = trip.trackPoints.map(TrackPointPayload.init)
        self.photos = (entity.photos?.array as? [TripPhotoEntity])?.compactMap { pe in
            guard let pid = pe.id, let fn = pe.filename, let ts = pe.timestamp else { return nil }
            return TripPhotoMetadataPayload(
                id: pid, filename: fn, caption: pe.caption,
                timestamp: ts, sortOrder: Int(pe.sortOrder))
        }
    }
}
