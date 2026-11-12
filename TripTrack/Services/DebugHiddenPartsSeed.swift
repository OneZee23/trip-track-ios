#if DEBUG
import Foundation
import CoreData
import CoreLocation

@MainActor
enum DebugHiddenPartsSeed {
    nonisolated static let launchArgument = "-seed-hidden-parts"

    static var isRequested: Bool { paintsSpeeds }

    /// The demo route is drawn in speed colours, but the launch post-processing rewrites the speeds
    /// `seedMissingTrackPointSpeeds` stores, and without them the visible runs read as grey road-gap
    /// dashes. So the reader paints them on the way out, in DEBUG runs with this flag only; the read
    /// path of every other run is the plain one.
    nonisolated static var paintsSpeeds: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains(launchArgument) || arguments.contains("-seed-hidden-parts-fresh")
    }

    nonisolated static func paintingSpeeds(_ points: [TrackPoint]) -> [TrackPoint] {
        points.enumerated().map { index, point in
            guard point.speed <= 0 else { return point }
            let progress = Double(index) / Double(max(1, points.count - 1))
            return TrackPoint(
                id: point.id, latitude: point.latitude, longitude: point.longitude,
                altitude: point.altitude, speed: 4.0 + 28.0 * abs(sin(progress * .pi * 1.4)), course: point.course,
                horizontalAccuracy: point.horizontalAccuracy, timestamp: point.timestamp,
                isInterpolated: point.isInterpolated, recordingSegmentIndex: point.recordingSegmentIndex
            )
        }
    }

    static func seed() {
        let repository = CoreDataTripRepository(persistenceController: .shared)
        let trips = repository.fetchTrips(limit: 500, offset: 0)
        for trip in trips where trip.endDate != nil {
            repository.seedMissingTrackPointSpeeds(for: trip.id)
        }
        let fixtureID = seedParkedTailTrip()
        guard let trip = repository.fetchTripDetail(id: fixtureID), trip.trackPoints.count >= 6 else { return }
        let start = trip.trackPoints[trip.trackPoints.count / 3].timestamp
        let end = trip.trackPoints[(trip.trackPoints.count * 2) / 3].timestamp
        let arguments = ProcessInfo.processInfo.arguments
        let parts = arguments.contains("-seed-hidden-parts-fresh")
            ? TripHiddenParts(startMetres: 0, endMetres: 0)
            : TripHiddenParts(
                startMetres: 500,
                endMetres: 1_000,
                sections: [HiddenSection(id: UUID(), from: start, to: end)],
                numbersVisibleOnly: false)
        repository.updateHiddenParts(for: trip.id, parts: parts)
        if arguments.contains("-seed-filming-mode") {
            let centre = PlaceManager.shared.places.first?.coordinate
                ?? trip.trackPoints.first?.coordinate
            if let centre {
                var home = HomeSettings.load()
                home.latitude = centre.latitude
                home.longitude = centre.longitude
                home.radius = .yard
                home.trimsPublicTracks = true
                home.save()
            }
        }
        UserDefaults.standard.set(trip.id.uuidString, forKey: "debug.hiddenParts.tripId")
    }

    private static let parkedTailTripID = UUID(uuidString: "09500000-0000-4000-8000-000000000001")!

    /// A fixed route plus five minutes of GPS jitter makes the parked-tail
    /// boundary reproducible in map and editor screenshots.
    private static func seedParkedTailTrip() -> UUID {
        let context = PersistenceController.shared.container.viewContext
        let request = NSFetchRequest<TripEntity>(entityName: "TripEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", parkedTailTripID as CVarArg)
        if let existing = try? context.fetch(request).first {
            if existing.orderedTrackPoints.count == 207 { return parkedTailTripID }
            context.delete(existing)
        }

        let trip = TripEntity(context: context)
        let start = Date().addingTimeInterval(-3_600)
        trip.id = parkedTailTripID
        trip.startDate = start
        trip.endDate = start.addingTimeInterval(2_420)
        trip.title = "Route with a parked tail"
        trip.region = "Debug"
        trip.isPrivate = true
        trip.isTrackProcessed = true

        let waypoints: [(Double, Double)] = [(55.700, 37.500), (55.737, 37.555), (55.775, 37.610), (55.812, 37.665)]
        let routePointCount = 201
        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(routePointCount + 6)
        for index in 0..<routePointCount {
            let progress = Double(index) / Double(routePointCount - 1) * Double(waypoints.count - 1)
            let segment = min(waypoints.count - 2, Int(progress))
            let fraction = progress - Double(segment)
            let from = waypoints[segment]
            let to = waypoints[segment + 1]
            coordinates.append(CLLocationCoordinate2D(
                latitude: from.0 + (to.0 - from.0) * fraction,
                longitude: from.1 + (to.1 - from.1) * fraction))
        }
        let endpoint = coordinates[routePointCount - 1]
        let jitter: [(Double, Double)] = [(0, 0), (0.00008, 0.00004), (-0.00006, 0.0001),
                                         (0.00012, -0.00005), (-0.0001, -0.00006), (0.00004, 0.00008)]
        for offset in jitter {
            coordinates.append(CLLocationCoordinate2D(latitude: endpoint.latitude + offset.0,
                                                       longitude: endpoint.longitude + offset.1))
        }

        for (index, coordinate) in coordinates.enumerated() {
            let point = TrackPointEntity(context: context)
            point.id = UUID()
            point.latitude = coordinate.latitude
            point.longitude = coordinate.longitude
            point.altitude = 150
            point.speed = index < routePointCount ? 8 : 0.4
            point.course = 45
            point.horizontalAccuracy = 5
            point.timestamp = start.addingTimeInterval(index < routePointCount
                ? Double(index) * 10
                : 2_000 + Double(index - routePointCount + 1) * 60)
            point.trip = trip
        }
        trip.distance = GeometryUtils.polylineLength(coordinates)
        trip.averageSpeed = 8
        trip.maxSpeed = 8
        trip.previewPolyline = Trip.encodePolyline(coordinates)
        try? context.save()
        return parkedTailTripID
    }
}
#endif
