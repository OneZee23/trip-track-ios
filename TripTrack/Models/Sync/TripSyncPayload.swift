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
    /// 0.5.6+ extended metrics — computed locally from track points before
    /// upload so the server can echo them back on /social/feed without
    /// having to fetch + reduce track points for every reader. Optional in
    /// the wire format for forward/backward compat with older servers.
    let maxAltitude: Double?
    let drivingTime: Int?
    let stoppedTime: Int?
    let region: String?
    let isPrivate: Bool
    let vehicleId: UUID?
    let fuelCurrency: String?
    let previewPolyline: String?
    let badgesJson: String?
    let xpEarned: Int?
    let conflictVersion: Int
    let lastModifiedAt: Date
    /// When the server first accepted this trip.
    ///
    /// The backend has always sent it — `serializeTrip` emits it on
    /// `/sync/pull` and `/trips/detail` — and the client simply never decoded
    /// it, so every trip that arrived by pull carried a nil `serverCreatedAt`
    /// locally. That nil is what made deleting a pulled trip take the "it was
    /// never on the server" short-circuit, leaving the row alive server-side
    /// forever. Optional because an older server omits it and because locally
    /// built upload payloads have nothing to put here yet.
    let serverCreatedAt: Date?
    // Optional: server omits track points in sync/pull responses (delta sync returns metadata only).
    // Present on upload (client → server) and on /trips/detail response.
    let trackPoints: [TrackPointPayload]?
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
        // Extended metrics — derived from track points. Send only when we
        // have data to compute from; empty-track-point trips (manual entry,
        // pre-0.5.6 imports) get nil so the server doesn't store a misleading
        // "0" that the social UI would later have to special-case.
        if !trip.trackPoints.isEmpty {
            self.maxAltitude = trip.trackPoints.map(\.altitude).max()
            let split = TripSyncPayload.computeMovementSplit(trip.trackPoints)
            self.drivingTime = Int(split.driving)
            self.stoppedTime = Int(split.stopped)
        } else {
            self.maxAltitude = nil
            self.drivingTime = nil
            self.stoppedTime = nil
        }
        self.region = trip.region
        self.isPrivate = trip.isPrivate
        self.vehicleId = trip.vehicleId
        self.fuelCurrency = trip.fuelCurrency
        self.previewPolyline = trip.previewPolyline?.base64EncodedString()
        self.badgesJson = entity.badgesJSON
        self.xpEarned = Int(entity.xpEarned)
        self.conflictVersion = Int(entity.conflictVersion)
        self.lastModifiedAt = entity.lastModifiedAt ?? Date()
        self.serverCreatedAt = entity.serverCreatedAt
        self.trackPoints = trip.trackPoints.map(TrackPointPayload.init)
        self.photos = (entity.photos?.array as? [TripPhotoEntity])?.compactMap { pe in
            guard let pid = pe.id, let fn = pe.filename, let ts = pe.timestamp else { return nil }
            return TripPhotoMetadataPayload(
                id: pid, filename: fn, caption: pe.caption,
                timestamp: ts, sortOrder: Int(pe.sortOrder))
        }
    }

    /// Mirrors `Trip.movementSplit` — duplicated here (not called through the
    /// Trip getter) because `Trip.movementSplit` is private and we want to
    /// keep the computation locally side-effect-free, with no reliance on
    /// CoreData faulting behaviour at upload time.
    private static func computeMovementSplit(_ points: [TrackPoint]) -> (driving: TimeInterval, stopped: TimeInterval) {
        guard points.count >= 2 else { return (0, 0) }
        let idleSpeedKmh = 5.0
        let maxGap: TimeInterval = 60
        var drv: TimeInterval = 0
        var stp: TimeInterval = 0
        for i in 1..<points.count {
            let dt = points[i].timestamp.timeIntervalSince(points[i - 1].timestamp)
            guard dt > 0, dt <= maxGap else { continue }
            let avgKmh = ((points[i].speed + points[i - 1].speed) / 2.0) * 3.6
            if avgKmh < idleSpeedKmh {
                stp += dt
            } else {
                drv += dt
            }
        }
        return (drv, stp)
    }
}
