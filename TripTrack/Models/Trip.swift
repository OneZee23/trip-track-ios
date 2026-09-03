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
    /// Whether a PERSON put that title there, as opposed to the app stamping
    /// the start date at save time.
    ///
    /// Saving a trip always writes a title («14 Jun, 12:31»), so "has a title"
    /// never meant "is named". The screens used to tell the two apart by
    /// re-formatting `startDate` and string-matching it — a guess, and one that
    /// erased a name the moment someone deliberately typed that exact string.
    /// Intent is not derivable from the text, so it is stored: false for the
    /// app's stamp, true for anything saved through the editor. Trips saved
    /// before the flag existed carry `false`, so they are still classified at
    /// read time by `TripAutoTitle.isAuto` — see `hasDisplayableName`. Nothing
    /// guesses about a trip named since.
    var titleIsCustom: Bool = false
    var tripDescription: String?
    var fuelUsed: Double
    var elevation: Double
    var region: String?
    var isPrivate: Bool
    /// Поездка, где человек был ПАССАЖИРОМ: такси, автобус, чужая машина.
    ///
    /// Отдельная сущность от «Без транспорта»: то означает «не указал машину»,
    /// а это — «ехал не за рулём». Разница видна в пробеге: такие километры
    /// идут в статистику (человек там был), но не наматывают ничью машину.
    var isTransfer: Bool = false
    var vehicleId: UUID?
    var fuelCurrency: String?
    var previewPolyline: Data?
    var earnedBadgeIds: [String]
    /// XP this single trip was worth, stamped when it finished.
    ///
    /// Kept on the trip rather than only summed into the profile because it is
    /// the only way to answer «what level was I when I drove this?» — the
    /// profile stores one running total and cannot be rewound. Zero for trips
    /// written before the field existed and for anything restored from a
    /// server that does not send it.
    var xpEarned: Int
    /// Offline CACHE of the server's companion roster, for the viewer's OWN
    /// trips only — see `TripCompanion`. Not the source of truth
    /// (`/companions/list` via `CompanionsStore` is); this is what lets the
    /// companions card draw something when that request has no network.
    var companions: [TripCompanion] = []
    /// Whether this trip actually has a row on the server —
    /// `TripEntity.serverCreatedAt != nil` for a local trip (see
    /// `CoreDataTripRepository.tripFromEntity`), always `true` for a trip
    /// adapted from the feed/social API (`Trip(social:)`) since it could
    /// only have arrived here BY existing server-side.
    ///
    /// Exists so a screen can tell "this trip cannot possibly have
    /// server-only state yet" (companions, a companion's remote-only
    /// photos) apart from "it can, and today's fetch just came back empty
    /// or failed" — asking the server about either for a trip that was
    /// never published (cloud sync starts OFF; new trips are created
    /// private) always answers `TRIP_NOT_FOUND`, which used to render as a
    /// permanent, unfixable error on what is the app's DEFAULT state, not
    /// an edge case. Defaults `false`: a freshly recorded trip has no
    /// `serverCreatedAt` until it actually uploads.
    var isOnServer: Bool = false

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
    private var movementSplit: (driving: TimeInterval, stopped: TimeInterval, movingDistance: Double) {
        guard trackPoints.count >= 2 else { return (0, 0, 0) }
        let idleSpeedKmh = 5.0
        let maxGap: TimeInterval = 60
        var drv: TimeInterval = 0
        var stp: TimeInterval = 0
        var movingDist: Double = 0
        for i in 1..<trackPoints.count {
            let dt = trackPoints[i].timestamp.timeIntervalSince(trackPoints[i - 1].timestamp)
            guard dt > 0, dt <= maxGap else { continue }
            let avgKmh = ((trackPoints[i].speed + trackPoints[i - 1].speed) / 2.0) * 3.6
            if avgKmh < idleSpeedKmh {
                stp += dt
            } else {
                // Accumulate distance ONLY over the same <=60s moving segments that
                // drivingTime counts, so the moving average stays consistent on
                // sparse-GPS trips (the full trip distance includes long cross-gap
                // segments that drivingTime excludes — dividing by it would inflate).
                let a = CLLocation(latitude: trackPoints[i - 1].latitude, longitude: trackPoints[i - 1].longitude)
                let b = CLLocation(latitude: trackPoints[i].latitude, longitude: trackPoints[i].longitude)
                let segDist = b.distance(from: a)
                // Reject GPS-teleport segments: a stale/low reported .speed paired
                // with a huge geometric jump (multipath, dropout snap-back) would
                // otherwise inflate BOTH drivingTime and movingDist, spiking the
                // moving average. Shared teleport ceiling (TripDistanceGate) — dt is
                // already guaranteed > 0 here (guarded above), so this is the
                // implied-speed gate, identical to the distance-stat paths.
                if !TripDistanceGate.isPlausibleSegment(meters: segDist, dt: dt) { continue }
                drv += dt
                movingDist += segDist
            }
        }
        return (drv, stp, movingDist)
    }

    var drivingTime: TimeInterval { movementSplit.driving }
    var stoppedTime: TimeInterval { movementSplit.stopped }

    /// Average speed over moving time only — distance covered WHILE MOVING divided
    /// by driving time (both exclude idle stretches and >60s gaps). The
    /// "технической / чистого хода" speed. Falls back to the overall average when
    /// there are no track points to split (e.g. a trip synced from another device
    /// with preview-only geometry).
    var movingAverageSpeedKmh: Double {
        let split = movementSplit
        return split.driving > 0 ? (split.movingDistance / split.driving) * 3.6 : averageSpeedKmh
    }

    /// Average speed for display, honoring the user's chosen mode.
    func displayAverageSpeedKmh(_ mode: AvgSpeedMode) -> Double {
        mode == .moving ? movingAverageSpeedKmh : averageSpeedKmh
    }

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
        // A zero component is noise, not precision: «4 мин 0 сек» and «2 ч 0
        // мин» both spend a word saying nothing.
        let h = AppStrings.hoursUnitShort(lang)
        let m = AppStrings.minutesUnitShort(lang)
        let s = AppStrings.secondsUnitShort(lang)
        if hours > 0 {
            if minutes == 0 { return "\(hours) \(h)" }
            return "\(hours) \(h) \(minutes) \(m)"
        }
        if minutes > 0 {
            if secs == 0 { return "\(minutes) \(m)" }
            return "\(minutes) \(m) \(secs) \(s)"
        }
        return "\(secs) \(s)"
    }

    init(id: UUID = UUID(), startDate: Date = Date(), endDate: Date? = nil,
         distance: Double = 0, maxSpeed: Double = 0, averageSpeed: Double = 0,
         trackPoints: [TrackPoint] = [], photos: [TripPhoto] = [],
         title: String? = nil, titleIsCustom: Bool = false,
         tripDescription: String? = nil,
         fuelUsed: Double = 0, elevation: Double = 0,
         region: String? = nil, isPrivate: Bool = true,
         isTransfer: Bool = false, vehicleId: UUID? = nil,
         fuelCurrency: String? = nil,
         previewPolyline: Data? = nil, earnedBadgeIds: [String] = [],
         xpEarned: Int = 0,
         companions: [TripCompanion] = [], isOnServer: Bool = false) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.distance = distance
        self.maxSpeed = maxSpeed
        self.averageSpeed = averageSpeed
        self.trackPoints = trackPoints
        self.photos = photos
        self.title = title
        self.titleIsCustom = titleIsCustom
        self.tripDescription = tripDescription
        self.fuelUsed = fuelUsed
        self.elevation = elevation
        self.region = region
        self.isPrivate = isPrivate
        self.isTransfer = isTransfer
        self.vehicleId = vehicleId
        self.fuelCurrency = fuelCurrency
        self.previewPolyline = previewPolyline
        self.earnedBadgeIds = earnedBadgeIds
        self.xpEarned = xpEarned
        self.companions = companions
        self.isOnServer = isOnServer
    }

    var earnedBadges: [Badge] {
        let allBadges = Badge.all
        return earnedBadgeIds.compactMap { id in allBadges.first { $0.id == id } }
    }

    /// Whether this trip carries a NAME — something to print as a heading —
    /// rather than just the date the app stamped on it at save time.
    ///
    /// Three kinds of title reach this property, and only one of them is not a
    /// name:
    ///   • typed by a person in the editor      → a name, whatever it says
    ///   • written by geocoding («Краснодар → Геленджик») → a name
    ///   • the start date, stamped when no place could be resolved → NOT a name
    ///
    /// `titleIsCustom` settles the first case as a fact, which a string
    /// comparison never could: someone who deliberately types «14 Jun, 12:31»
    /// means it, and used to have it silently swallowed. The date check still
    /// covers the third, because that string is one the app wrote itself.
    var hasDisplayableName: Bool {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return false
        }
        if titleIsCustom { return true }
        return !TripAutoTitle.isAuto(t, startDate: startDate)
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
