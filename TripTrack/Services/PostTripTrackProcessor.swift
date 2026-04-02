import Foundation
import CoreData
import CoreLocation

/// Post-trip track reconstruction: fills GPS gaps with interpolated points
/// and regenerates trip statistics.
final class PostTripTrackProcessor {

    private let persistenceController: PersistenceController

    /// Minimum time gap between consecutive points to trigger interpolation (seconds)
    private let gapThreshold: TimeInterval = 3.0

    /// Maximum distance for interpolation — beyond this the gap is left as-is (meters)
    private let maxInterpolationDistance: Double = 5000.0

    /// Time interval between interpolated points (seconds)
    private let interpolationInterval: TimeInterval = 2.0

    /// Max single-segment distance for stats (rejects GPS jumps)
    private let maxSegmentDistance: Double = 1000.0

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Process a single trip: fill gaps, regenerate polyline, recalculate stats.
    func processTrip(_ tripId: UUID) async {
        await MainActor.run {
            processOnContext(tripId)
        }
    }

    /// Process all unprocessed trips (call at app launch).
    func processUnprocessedTrips() async {
        await MainActor.run {
            let context = persistenceController.container.viewContext
            let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
            request.predicate = NSPredicate(
                format: "endDate != nil AND isTrackProcessed == NO"
            )

            guard let entities = try? context.fetch(request) else { return }
            for entity in entities {
                guard let id = entity.id else { continue }
                processOnContext(id)
            }
        }
    }

    // MARK: - Core Processing

    private func processOnContext(_ tripId: UUID) {
        let context = persistenceController.container.viewContext
        let request: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", tripId as CVarArg)

        guard let entity = try? context.fetch(request).first else { return }

        // Skip if already processed
        guard !entity.isTrackProcessed else { return }

        // Load original (non-interpolated) track points sorted by timestamp
        guard let allPoints = entity.trackPoints?.array as? [TrackPointEntity] else { return }
        let originalPoints = allPoints
            .filter { !$0.isInterpolated }
            .sorted { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }

        guard originalPoints.count >= 2 else {
            entity.isTrackProcessed = true
            persistenceController.save()
            return
        }

        // Find and fill gaps
        var interpolatedEntities: [TrackPointEntity] = []

        for i in 0..<(originalPoints.count - 1) {
            let p1 = originalPoints[i]
            let p2 = originalPoints[i + 1]

            guard let t1 = p1.timestamp, let t2 = p2.timestamp else { continue }
            let dt = t2.timeIntervalSince(t1)
            guard dt > gapThreshold else { continue }

            // Check distance
            let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
            let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
            let distance = loc2.distance(from: loc1)
            guard distance <= maxInterpolationDistance else { continue }

            // Catmull-Rom needs 4 control points: p0, p1, p2, p3
            let p0 = i > 0 ? originalPoints[i - 1] : p1
            let p3 = (i + 2) < originalPoints.count ? originalPoints[i + 2] : p2

            // Number of interpolated points
            let numPoints = max(1, Int(dt / interpolationInterval) - 1)

            for j in 1...numPoints {
                let t = Double(j) / Double(numPoints + 1)
                let timestamp = t1.addingTimeInterval(dt * t)

                // Catmull-Rom interpolation for coordinates
                let coord = catmullRom(
                    p0: CLLocationCoordinate2D(latitude: p0.latitude, longitude: p0.longitude),
                    p1: CLLocationCoordinate2D(latitude: p1.latitude, longitude: p1.longitude),
                    p2: CLLocationCoordinate2D(latitude: p2.latitude, longitude: p2.longitude),
                    p3: CLLocationCoordinate2D(latitude: p3.latitude, longitude: p3.longitude),
                    t: t
                )

                // Linear interpolation for other properties
                let speed = p1.speed + (p2.speed - p1.speed) * t
                let altitude = p1.altitude + (p2.altitude - p1.altitude) * t
                let course = interpolateCourse(from: p1.course, to: p2.course, t: t)

                let pointEntity = TrackPointEntity(context: context)
                pointEntity.id = UUID()
                pointEntity.latitude = coord.latitude
                pointEntity.longitude = coord.longitude
                pointEntity.altitude = altitude
                pointEntity.speed = speed
                pointEntity.course = course
                pointEntity.horizontalAccuracy = 0
                pointEntity.timestamp = timestamp
                pointEntity.isInterpolated = true
                pointEntity.trip = entity

                interpolatedEntities.append(pointEntity)
            }
        }

        // Regenerate preview polyline (uses all track points including interpolated)
        regeneratePreviewPolyline(for: entity)

        // Recalculate stats
        recalculateStats(for: entity)

        // Mark as processed
        entity.isTrackProcessed = true
        entity.lastModifiedAt = Date()
        persistenceController.save()
    }

    // MARK: - Catmull-Rom Interpolation

    private func catmullRom(
        p0: CLLocationCoordinate2D,
        p1: CLLocationCoordinate2D,
        p2: CLLocationCoordinate2D,
        p3: CLLocationCoordinate2D,
        t: Double
    ) -> CLLocationCoordinate2D {
        let t2 = t * t
        let t3 = t2 * t

        let lat = 0.5 * (
            (2 * p1.latitude) +
            (-p0.latitude + p2.latitude) * t +
            (2 * p0.latitude - 5 * p1.latitude + 4 * p2.latitude - p3.latitude) * t2 +
            (-p0.latitude + 3 * p1.latitude - 3 * p2.latitude + p3.latitude) * t3
        )

        let lon = 0.5 * (
            (2 * p1.longitude) +
            (-p0.longitude + p2.longitude) * t +
            (2 * p0.longitude - 5 * p1.longitude + 4 * p2.longitude - p3.longitude) * t2 +
            (-p0.longitude + 3 * p1.longitude - 3 * p2.longitude + p3.longitude) * t3
        )

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Interpolate course (heading) handling the 0°/360° wraparound
    private func interpolateCourse(from c1: Double, to c2: Double, t: Double) -> Double {
        guard c1 >= 0 && c2 >= 0 else { return max(c1, c2) }

        var delta = c2 - c1
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        var result = c1 + delta * t
        if result < 0 { result += 360 }
        if result >= 360 { result -= 360 }
        return result
    }

    // MARK: - Preview Polyline

    private func regeneratePreviewPolyline(for entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count >= 2 else { return }

        let sorted = points.sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }
        let coords = sorted.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        let simplified = GeometryUtils.simplifyRDP(coords, epsilon: 0.00003)
        entity.previewPolyline = Trip.encodePolyline(simplified)
    }

    // MARK: - Stats Recalculation

    private func recalculateStats(for entity: TripEntity) {
        guard let points = entity.trackPoints?.array as? [TrackPointEntity],
              points.count > 1 else { return }

        let sorted = points.sorted {
            ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast)
        }

        var totalDistance: Double = 0
        var maxSpeed: Double = 0

        for i in 1..<sorted.count {
            let prev = CLLocation(latitude: sorted[i-1].latitude, longitude: sorted[i-1].longitude)
            let curr = CLLocation(latitude: sorted[i].latitude, longitude: sorted[i].longitude)
            let segmentDist = curr.distance(from: prev)

            guard segmentDist < maxSegmentDistance else { continue }

            if let prevTS = sorted[i-1].timestamp, let currTS = sorted[i].timestamp {
                let dt = currTS.timeIntervalSince(prevTS)
                if dt > 0 && segmentDist / dt > 83.0 { continue }
            }

            totalDistance += segmentDist

            // Only count speed from non-interpolated points
            if !sorted[i].isInterpolated {
                maxSpeed = max(maxSpeed, sorted[i].speed)
            }
        }

        entity.distance = totalDistance
        entity.maxSpeed = maxSpeed

        if let start = entity.startDate, let end = entity.endDate {
            let elapsed = end.timeIntervalSince(start)
            entity.averageSpeed = elapsed > 0 ? totalDistance / elapsed : 0
        }
    }
}
