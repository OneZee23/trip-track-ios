import Foundation
import CoreLocation

struct Trip: Identifiable, Codable {
    let id: UUID
    var startDate: Date
    var endDate: Date?
    var distance: Double // meters
    var maxSpeed: Double // m/s
    var averageSpeed: Double // m/s
    var trackPoints: [TrackPoint]
    var photos: [TripPhoto]

    var title: String?
    var tripDescription: String?
    var fuelUsed: Double
    var elevation: Double
    var region: String?
    var isPrivate: Bool
    var vehicleId: UUID?
    var fuelCurrency: String?
    var previewPolyline: Data?
    var earnedBadgeIds: [String]

    /// Decoded simplified coordinates for feed card route previews.
    /// Hits an `NSCache` keyed by trip id so a feed scroll past 30 cards
    /// doesn't redecode 30 polylines × 60Hz. Cache is bounded so memory
    /// stays in check across long sessions; eviction is automatic on
    /// memory pressure.
    var previewCoordinates: [CLLocationCoordinate2D] {
        guard let data = previewPolyline else { return trackPoints.map(\.coordinate) }
        if let cached = Self.previewCache.object(forKey: id as NSUUID) {
            return cached.coords
        }
        let coords = Self.decodePolyline(data)
        Self.previewCache.setObject(CoordsBox(coords: coords), forKey: id as NSUUID)
        return coords
    }

    /// Wrapper class because `NSCache` requires an `AnyObject` value type.
    private final class CoordsBox {
        let coords: [CLLocationCoordinate2D]
        init(coords: [CLLocationCoordinate2D]) { self.coords = coords }
    }

    private static let previewCache: NSCache<NSUUID, CoordsBox> = {
        let cache = NSCache<NSUUID, CoordsBox>()
        cache.countLimit = 200
        return cache
    }()

    /// Drops cached coords for a single trip — called when the trip is
    /// edited / its polyline regenerated. Without this, the next feed
    /// render shows the stale pre-edit shape until app relaunch.
    static func invalidatePreviewCache(for tripId: UUID) {
        previewCache.removeObject(forKey: tripId as NSUUID)
    }

    /// Encode an array of coordinates into compact binary data (pairs of Float32).
    static func encodePolyline(_ coords: [CLLocationCoordinate2D]) -> Data {
        var data = Data(capacity: coords.count * 8)
        for coord in coords {
            var lat = Float32(coord.latitude)
            var lon = Float32(coord.longitude)
            data.append(Data(bytes: &lat, count: 4))
            data.append(Data(bytes: &lon, count: 4))
        }
        return data
    }

    /// Decode binary polyline data back into coordinates. Bulk-binds the
    /// whole `Data` blob as `Float32` once instead of per-coord
    /// `withUnsafeMutableBytes` round-trips.
    static func decodePolyline(_ data: Data) -> [CLLocationCoordinate2D] {
        guard data.count >= 8, data.count % 8 == 0 else { return [] }
        let count = data.count / 8
        var coords: [CLLocationCoordinate2D] = []
        coords.reserveCapacity(count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let buffer = raw.bindMemory(to: Float32.self)
            // Two Float32 per coord: lat, lon. Iterate paired indices.
            for i in stride(from: 0, to: buffer.count, by: 2) {
                let lat = Double(buffer[i])
                let lon = Double(buffer[i + 1])
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
        }
        return coords
    }

    var isActive: Bool {
        endDate == nil
    }

    var duration: TimeInterval {
        let end = endDate ?? Date()
        return end.timeIntervalSince(startDate)
    }

    var distanceKm: Double {
        distance / 1000.0
    }

    var maxSpeedKmh: Double {
        maxSpeed * 3.6
    }

    var averageSpeedKmh: Double {
        averageSpeed * 3.6
    }

    /// Time spent actually moving vs sitting stationary (engine running but
    /// not making progress — traffic, lights, parked-but-recording). Computed
    /// from track points: walks pairs of points, classifies each gap by the
    /// pair's speed, and ignores gaps >60s as pauses/GPS dropouts so a
    /// lunch-break-with-pause-pressed doesn't inflate stoppedTime.
    ///
    /// Why a stat split instead of a smarter fuel formula: any GPS-only fuel
    /// model has ±30% intrinsic error (cold-start, idle rate variance per
    /// engine, acceleration profile). Showing "Driving 1h / Stopped 4h" is
    /// honest data the user calibrates their own intuition against.
    private var movementSplit: (driving: TimeInterval, stopped: TimeInterval) {
        guard trackPoints.count >= 2 else { return (0, 0) }
        let idleSpeedKmh = 5.0
        let maxGap: TimeInterval = 60
        var drv: TimeInterval = 0
        var stp: TimeInterval = 0
        for i in 1..<trackPoints.count {
            let dt = trackPoints[i].timestamp.timeIntervalSince(trackPoints[i - 1].timestamp)
            guard dt > 0, dt <= maxGap else { continue }
            let avgKmh = ((trackPoints[i].speed + trackPoints[i - 1].speed) / 2.0) * 3.6
            if avgKmh < idleSpeedKmh {
                stp += dt
            } else {
                drv += dt
            }
        }
        return (drv, stp)
    }

    var drivingTime: TimeInterval { movementSplit.driving }
    var stoppedTime: TimeInterval { movementSplit.stopped }

    var formattedDuration: String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func formattedDurationHuman(_ lang: LanguageManager.Language) -> String {
        Self.formattedTimeHuman(duration, lang: lang)
    }

    /// Formats an arbitrary time interval the same way `formattedDurationHuman`
    /// does — for the trip's drivingTime / stoppedTime split which needs the
    /// same compact "X ч Y мин" rendering as the duration card next to it.
    static func formattedTimeHuman(_ seconds: TimeInterval, lang: LanguageManager.Language) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return lang == .ru ? "\(hours) ч \(minutes) мин" : "\(hours) h \(minutes) min"
        }
        if minutes > 0 {
            return lang == .ru ? "\(minutes) мин \(secs) сек" : "\(minutes) min \(secs) sec"
        }
        return lang == .ru ? "\(secs) сек" : "\(secs) sec"
    }

    init(id: UUID = UUID(), startDate: Date = Date(), endDate: Date? = nil,
         distance: Double = 0, maxSpeed: Double = 0, averageSpeed: Double = 0,
         trackPoints: [TrackPoint] = [], photos: [TripPhoto] = [],
         title: String? = nil, tripDescription: String? = nil,
         fuelUsed: Double = 0, elevation: Double = 0,
         region: String? = nil, isPrivate: Bool = true, vehicleId: UUID? = nil,
         fuelCurrency: String? = nil,
         previewPolyline: Data? = nil, earnedBadgeIds: [String] = []) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.averageSpeed = averageSpeed
        self.trackPoints = trackPoints
        self.photos = photos
        self.title = title
        self.tripDescription = tripDescription
        self.fuelUsed = fuelUsed
        self.elevation = elevation
        self.region = region
        self.isPrivate = isPrivate
        self.vehicleId = vehicleId
        self.fuelCurrency = fuelCurrency
        self.previewPolyline = previewPolyline
        self.earnedBadgeIds = earnedBadgeIds
    }

    var earnedBadges: [Badge] {
        let allBadges = Badge.all
        return earnedBadgeIds.compactMap { id in allBadges.first { $0.id == id } }
    }
}

extension Trip {
    /// Trips classified as junk are auto-discarded after recording. Two cases:
    /// 1. Parking-lot manoeuvres — short distance AND short duration.
    /// 2. CMMotion misfires — capped at walking speed but recorded for long
    ///    enough that they're clearly not a real drive.
    var isJunk: Bool {
        TripJunkClassifier.isJunk(
            distanceMeters: distance,
            durationSeconds: duration,
            maxSpeedKmh: maxSpeedKmh
        )
    }
}

/// Shared classifier so post-trip cleanup (MapViewModel.stopRecording) and
/// orphan recovery (TripManager.cleanupOrphanedTrips) can't drift apart.
enum TripJunkClassifier {
    static func isJunk(distanceMeters: Double, durationSeconds: TimeInterval, maxSpeedKmh: Double) -> Bool {
        let isParkingManeuver = distanceMeters < AutoTripPolicy.junkTripMinDistance
            && durationSeconds < AutoTripPolicy.junkTripMinDuration
        let isWalkingMisfire = maxSpeedKmh < AutoTripPolicy.junkTripWalkingSpeedKmh
            && durationSeconds > AutoTripPolicy.junkTripWalkingMinDuration
        return isParkingManeuver || isWalkingMisfire
    }
}

// Manual Equatable: excludes trackPoints (large array kills SwiftUI diffing)
// and rarely-changing fields (tripDescription, isPrivate, vehicleId, fuelUsed,
// elevation, maxSpeed, averageSpeed) that don't affect feed card rendering.
// Includes previewPolyline because async backfill updates it.
extension Trip: Equatable {
    static func == (lhs: Trip, rhs: Trip) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.distance == rhs.distance &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.region == rhs.region &&
        lhs.isPrivate == rhs.isPrivate &&
        lhs.photos.count == rhs.photos.count &&
        lhs.previewPolyline == rhs.previewPolyline
    }
}
