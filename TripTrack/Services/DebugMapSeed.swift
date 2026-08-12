#if DEBUG
import Foundation
import CoreData
import CoreLocation

/// Fills an empty simulator store with a believable set of drives so «Моя
/// карта» can actually be looked at — region fills, clusters, city dots, the
/// region card and the trip card all need real trips to exist.
///
/// Runs ONLY when the `-seed-map-demo` launch argument is present, which
/// nothing but a manual simulator run or a UI test ever passes, and is
/// compiled out of release builds entirely.
enum DebugMapSeed {
    static let launchArgument = "-seed-map-demo"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    private struct Route {
        let title: String
        let region: String
        let daysAgo: Int
        let waypoints: [(Double, Double)]
        /// How many times this road was driven. The fog of roads only means
        /// anything when some roads are worn — a commute has to outshine the
        /// one-off run to the sea.
        var repeats: Int = 1
    }

    /// Real roads around Krasnodar Krai, plus one in Rostov Oblast and one in
    /// Georgia, so the map has more than a single blob to show: several
    /// regions, a border crossing, and trips far enough apart to cluster.
    private static let routes: [Route] = [
        Route(title: "Краснодар → Геленджик", region: "Krasnodar Krai", daysAgo: 86,
              waypoints: [(45.035, 38.975), (44.900, 38.780), (44.780, 38.500),
                          (44.640, 38.230), (44.561, 38.077)]),
        Route(title: "Краснодар → Горячий Ключ", region: "Krasnodar Krai", daysAgo: 72,
              waypoints: [(45.035, 38.975), (44.900, 39.020), (44.760, 39.080), (44.630, 39.130)]),
        // The two repeated routes are also the most RECENT, which is what a
        // commute actually is — and it puts them at the top of the region
        // card's trip list, where the fog screenshot test can reach them.
        Route(title: "Утренний круг по бетонке", region: "Krasnodar Krai", daysAgo: 6,
              waypoints: [(45.035, 38.975), (45.090, 39.060), (45.120, 38.980),
                          (45.060, 38.900), (45.035, 38.975)], repeats: 22),
        Route(title: "На работу", region: "Krasnodar Krai", daysAgo: 2,
              waypoints: [(45.035, 38.975), (45.020, 39.030), (45.010, 39.090)], repeats: 9),
        // City blocks, not a highway — without something at this scale the
        // street-zoom screenshot is one line across empty farmland, which is
        // where the fog is easiest to get wrong and hardest to notice.
        Route(title: "По городу", region: "Krasnodar Krai", daysAgo: 1,
              waypoints: [(45.0355, 38.9750), (45.0355, 38.9820), (45.0310, 38.9820),
                          (45.0310, 38.9900), (45.0260, 38.9900), (45.0260, 38.9800),
                          (45.0300, 38.9800), (45.0300, 38.9720), (45.0355, 38.9720),
                          (45.0355, 38.9750)], repeats: 6),
        Route(title: "Геленджик → Джубга", region: "Krasnodar Krai", daysAgo: 54,
              waypoints: [(44.561, 38.077), (44.480, 38.300), (44.400, 38.520), (44.320, 38.700)]),
        Route(title: "Сочи → Красная Поляна", region: "Krasnodar Krai", daysAgo: 33,
              waypoints: [(43.585, 39.723), (43.560, 39.850), (43.600, 40.020),
                          (43.660, 40.130), (43.680, 40.200)]),
        Route(title: "Адлер → Сочи", region: "Krasnodar Krai", daysAgo: 30,
              waypoints: [(43.430, 39.920), (43.470, 39.870), (43.520, 39.800), (43.585, 39.723)]),
        Route(title: "Сочи → Лазаревское", region: "Krasnodar Krai", daysAgo: 21,
              waypoints: [(43.585, 39.723), (43.700, 39.560), (43.820, 39.400), (43.910, 39.330)]),
        Route(title: "Краснодар → Ростов-на-Дону", region: "Rostov Oblast", daysAgo: 14,
              waypoints: [(45.035, 38.975), (45.400, 39.100), (45.900, 39.300),
                          (46.500, 39.500), (47.222, 39.719)]),
        Route(title: "По Ростову", region: "Rostov Oblast", daysAgo: 12,
              waypoints: [(47.222, 39.719), (47.260, 39.760), (47.240, 39.820), (47.200, 39.740)]),
        Route(title: "Батуми → Кобулети", region: "Adjara", daysAgo: 5,
              waypoints: [(41.640, 41.640), (41.720, 41.700), (41.790, 41.760)]),
    ]

    static func run(
        persistence: PersistenceController = .shared,
        territory: TerritoryManager
    ) {
        let context = persistence.container.viewContext
        let existing: NSFetchRequest<TripEntity> = TripEntity.fetchRequest()
        existing.fetchLimit = 1
        if let found = try? context.count(for: existing), found > 0 { return }

        for route in routes {
        for pass in 0..<route.repeats {
            // Real GPS never repeats itself: every pass wanders a few metres
            // either side of the last one, all the way along. That wander is
            // exactly what the fog has to collapse, so the fixture has to
            // have it — a fixed per-pass offset would have let five tidy
            // parallel ribbons pass for one road.
            let coordinates = densify(route.waypoints, stepMeters: 400)
                .enumerated()
                .map { index, point -> CLLocationCoordinate2D in
                    let phase = Double(index) * 0.6 + Double(pass) * 1.7
                    return CLLocationCoordinate2D(
                        latitude: point.latitude + sin(phase) * 0.00008,
                        longitude: point.longitude + cos(phase * 1.3) * 0.00008
                    )
                }
            let start = Calendar.current.date(
                byAdding: .day, value: -(route.daysAgo + pass * 2), to: Date()) ?? Date()
            let seconds = Double(coordinates.count) * 24

            let trip = TripEntity(context: context)
            trip.id = UUID()
            trip.startDate = start
            trip.endDate = start.addingTimeInterval(seconds)
            trip.title = route.title
            trip.region = route.region
            trip.isPrivate = true
            trip.distance = pathLength(coordinates)
            trip.maxSpeed = 32
            trip.averageSpeed = trip.distance / max(seconds, 1)

            for (index, coordinate) in coordinates.enumerated() {
                let point = TrackPointEntity(context: context)
                point.id = UUID()
                point.latitude = coordinate.latitude
                point.longitude = coordinate.longitude
                point.altitude = 40
                // Enough spread that the speed gradient has something to show.
                point.speed = 14 + Double((index * 7) % 18)
                point.course = 0
                point.horizontalAccuracy = 5
                point.timestamp = start.addingTimeInterval(Double(index) * 24)
                point.trip = trip
                territory.recordVisit(coordinate: coordinate)
            }
        }
        }
        persistence.save()
    }

    // MARK: - Geometry

    /// Waypoints alone would leave 40 km between GPS points; the map needs a
    /// track, and the region attribution walks segment midpoints.
    private static func densify(
        _ waypoints: [(Double, Double)], stepMeters: Double
    ) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for i in 1..<waypoints.count {
            let a = CLLocationCoordinate2D(latitude: waypoints[i - 1].0, longitude: waypoints[i - 1].1)
            let b = CLLocationCoordinate2D(latitude: waypoints[i].0, longitude: waypoints[i].1)
            let steps = max(1, Int(GeometryUtils.haversineDistance(a, b) / stepMeters))
            for step in 0..<steps {
                let t = Double(step) / Double(steps)
                out.append(CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * t,
                    longitude: a.longitude + (b.longitude - a.longitude) * t
                ))
            }
        }
        if let last = waypoints.last {
            out.append(CLLocationCoordinate2D(latitude: last.0, longitude: last.1))
        }
        return out
    }

    private static func pathLength(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        return (1..<coordinates.count).reduce(0) {
            $0 + GeometryUtils.haversineDistance(coordinates[$1 - 1], coordinates[$1])
        }
    }
}
#endif
