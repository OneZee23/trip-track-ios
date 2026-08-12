import XCTest
import CoreLocation
import MapKit
@testable import TripTrack

/// The map screen is only as honest as its geometry: if a coordinate lands in
/// the wrong federal subject, every number on the region card is wrong and
/// nothing on screen says so. These tests pin the lookups that everything
/// else is built on.
final class MyMapAtlasTests: XCTestCase {

    private var atlas: RegionAtlas!

    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
        atlas = RegionAtlas.shared
        try XCTSkipUnless(atlas.isLoaded, "MapRegions.json missing from the test bundle")
    }

    // MARK: - Atlas

    func testAtlasLoadsRussianSubjects() {
        let russian = atlas.regions.filter { $0.countryCode == "RU" }
        // 83–86 depending on how Natural Earth counts the federal cities.
        XCTAssertGreaterThan(russian.count, 80)
        XCTAssertNotNil(atlas.region(id: "RU-KDA"))
    }

    /// The 1:50m cut of Natural Earth put Adler and Krasnaya Polyana outside
    /// Krasnodar Krai — the coastal strip was 128 points wide for the whole
    /// region. That is exactly the bug this asserts against.
    func testBlackSeaCoastResolvesToKrasnodarKrai() {
        let coastal = [
            ("Сочи", CLLocationCoordinate2D(latitude: 43.585, longitude: 39.723)),
            ("Адлер", CLLocationCoordinate2D(latitude: 43.430, longitude: 39.920)),
            ("Красная Поляна", CLLocationCoordinate2D(latitude: 43.680, longitude: 40.200)),
            ("Краснодар", CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)),
            ("Геленджик", CLLocationCoordinate2D(latitude: 44.561, longitude: 38.077)),
        ]
        for (name, coordinate) in coastal {
            XCTAssertEqual(atlas.region(containing: coordinate)?.id, "RU-KDA", "\(name)")
        }
    }

    func testNeighbouringRegionsAreDistinct() {
        let cases = [
            (CLLocationCoordinate2D(latitude: 47.222, longitude: 39.719), "RU-ROS"),
            (CLLocationCoordinate2D(latitude: 45.045, longitude: 41.969), "RU-STA"),
            (CLLocationCoordinate2D(latitude: 59.939, longitude: 30.315), "RU-SPE"),
        ]
        for (coordinate, expected) in cases {
            XCTAssertEqual(atlas.region(containing: coordinate)?.id, expected)
        }
    }

    func testAbroadResolvesToItsOwnCountry() {
        let batumi = CLLocationCoordinate2D(latitude: 41.640, longitude: 41.640)
        XCTAssertEqual(atlas.region(containing: batumi)?.countryCode, "GE")
    }

    func testOpenSeaHasNoRegion() {
        // Middle of the Black Sea.
        let sea = CLLocationCoordinate2D(latitude: 43.2, longitude: 34.5)
        XCTAssertNil(atlas.region(containing: sea))
    }

    func testCitiesAreAttachedToRegions() {
        let names = Set(atlas.cities(in: "RU-KDA").map(\.name))
        XCTAssertTrue(names.contains("Краснодар"))
        XCTAssertTrue(names.contains("Сочи"))
        XCTAssertGreaterThan(names.count, 15, "Krasnodar Krai should carry its whole city list")
    }

    func testFlagFromCountryCode() {
        XCTAssertEqual(RegionAtlas.flag(for: "RU"), "🇷🇺")
        XCTAssertEqual(RegionAtlas.flag(for: "GE"), "🇬🇪")
    }

    // MARK: - Exploration

    func testTripKilometresLandInTheRegionTheyWereDrivenIn() {
        // Krasnodar → Goryachy Klyuch, entirely inside Krasnodar Krai.
        let route = Self.line(
            from: CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            to: CLLocationCoordinate2D(latitude: 44.630, longitude: 39.130),
            steps: 40
        )
        let trip = Self.trip(route: route)
        let hashes = Set(route.map {
            GeohashEncoder.encode(latitude: $0.latitude, longitude: $0.longitude, precision: 6)
        })

        let exploration = MapExploration.build(trips: [trip], visitedHashes: hashes, atlas: atlas)

        XCTAssertEqual(exploration.regionCount, 1)
        let region = try? XCTUnwrap(exploration.region(id: "RU-KDA"))
        XCTAssertNotNil(region)
        XCTAssertEqual(region?.tripCount, 1)
        // ~50 km as the crow flies.
        XCTAssertEqual(region?.km ?? 0, 50, accuracy: 8)
        XCTAssertEqual(exploration.tripCount, 1)
        XCTAssertFalse(exploration.isEmpty)
    }

    func testCityIsOpenedWhenYouDroveThroughIt() {
        let route = Self.line(
            from: CLLocationCoordinate2D(latitude: 45.010, longitude: 38.950),
            to: CLLocationCoordinate2D(latitude: 45.060, longitude: 39.010),
            steps: 60
        )
        let hashes = Set(route.map {
            GeohashEncoder.encode(latitude: $0.latitude, longitude: $0.longitude, precision: 6)
        })
        let exploration = MapExploration.build(
            trips: [Self.trip(route: route)], visitedHashes: hashes, atlas: atlas)

        let krasnodar = exploration.region(id: "RU-KDA")?.cities.first { $0.name == "Краснодар" }
        XCTAssertNotNil(krasnodar, "driving across Krasnodar must open it")
        XCTAssertGreaterThan(krasnodar?.coverage ?? 0, 0)
        XCTAssertLessThanOrEqual(krasnodar?.coverage ?? 1, 1)
        // A single crossing is not the whole city.
        XCTAssertLessThan(krasnodar?.coverage ?? 1, 0.5)
    }

    /// A pause or a GPS glitch leaves a huge gap between two consecutive
    /// points. Counting it would credit every region on the straight line
    /// between them.
    func testTeleportSegmentsAreNotCounted() {
        let jump = [
            CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            CLLocationCoordinate2D(latitude: 55.755, longitude: 37.617),  // Moscow
        ]
        let exploration = MapExploration.build(
            trips: [Self.trip(route: jump)], visitedHashes: [], atlas: atlas)
        XCTAssertTrue(exploration.regions.isEmpty)
    }

    func testEmptyInputProducesEmptyExploration() {
        let exploration = MapExploration.build(trips: [], visitedHashes: [], atlas: atlas)
        XCTAssertTrue(exploration.isEmpty)
        XCTAssertEqual(exploration.regionCount, 0)
        XCTAssertEqual(exploration.totalKm, 0)
    }

    /// The map builds from the preview polyline alone. Loading every track
    /// point of every trip to attribute kilometres froze the main actor for
    /// seconds on a large library, so nothing here may reach for them again.
    func testExplorationNeedsNoTrackPoints() {
        let route = Self.line(
            from: CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            to: CLLocationCoordinate2D(latitude: 44.630, longitude: 39.130),
            steps: 40
        )
        var trip = Trip(startDate: Date(timeIntervalSince1970: 1_750_000_000), trackPoints: [])
        trip.distance = 50_000
        trip.previewPolyline = Trip.encodePolyline(route)

        let exploration = MapExploration.build(trips: [trip], visitedHashes: [], atlas: atlas)

        XCTAssertEqual(exploration.tripCount, 1)
        XCTAssertEqual(exploration.region(id: "RU-KDA")?.km ?? 0, 50, accuracy: 1)
        XCTAssertFalse(exploration.trips.first?.route.isEmpty ?? true,
                       "the pin still needs a route to draw and to be tapped on")
    }

    /// Region kilometres are the trip's REAL distance split by where the path
    /// spent its time. Summing the simplified preview's own segments instead
    /// quietly under-counts every bend in the road.
    func testRegionKilometresSplitTheTripsRealDistance() {
        // Krasnodar → Rostov-on-Don crosses into Rostov Oblast partway.
        let route = Self.line(
            from: CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            to: CLLocationCoordinate2D(latitude: 47.222, longitude: 39.719),
            steps: 120
        )
        var trip = Self.trip(route: route)
        trip.distance = 300_000

        let exploration = MapExploration.build(trips: [trip], visitedHashes: [], atlas: atlas)
        let total = exploration.regions.reduce(0) { $0 + $1.km }

        XCTAssertGreaterThanOrEqual(exploration.regionCount, 2, "the drive crosses a border")
        XCTAssertEqual(total, 300, accuracy: 1,
                       "the parts must add up to the distance actually driven")
        for region in exploration.regions {
            XCTAssertGreaterThan(region.km, 0)
            XCTAssertLessThan(region.km, 300)
        }
    }

    // MARK: - Bounds

    /// A trip that never moved collapses to a zero-size rect, and
    /// `setVisibleMapRect` answers that by zooming to the tightest level the
    /// map has — a grey screen with nothing on it.
    func testDegenerateBoundsStillGiveTheCameraSomethingToLookAt() {
        let point = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
        let rect = GeoBounds(covering: [point])?.mapRect
        let metre = MKMapPointsPerMeterAtLatitude(point.latitude)

        XCTAssertGreaterThan(rect?.width ?? 0, 100 * metre)
        XCTAssertGreaterThan(rect?.height ?? 0, 100 * metre)
        XCTAssertEqual(MKMapPoint(x: rect?.midX ?? 0, y: rect?.midY ?? 0).coordinate.latitude,
                       point.latitude, accuracy: 0.01)
    }

    func testGeoBoundsCoverAndMeasure() {
        let bounds = GeoBounds(covering: [
            CLLocationCoordinate2D(latitude: 44, longitude: 38),
            CLLocationCoordinate2D(latitude: 46, longitude: 40),
        ])
        XCTAssertEqual(bounds?.center.latitude ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(bounds?.nearestEdgeDistance(
            from: CLLocationCoordinate2D(latitude: 45, longitude: 39)) ?? 1, 0, accuracy: 0.001)
        XCTAssertGreaterThan(bounds?.nearestEdgeDistance(
            from: CLLocationCoordinate2D(latitude: 48, longitude: 39)) ?? 0, 100_000)
        XCTAssertNil(GeoBounds(covering: []))
    }

    func testZoomLevelThresholds() {
        XCTAssertEqual(MapZoomLevel.of(8), .far)
        XCTAssertEqual(MapZoomLevel.of(1.0), .region)
        XCTAssertEqual(MapZoomLevel.of(0.05), .close)
        XCTAssertTrue(MapZoomLevel.far < MapZoomLevel.region)
    }

    // MARK: - Fixtures

    private static func line(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        steps: Int
    ) -> [CLLocationCoordinate2D] {
        (0...steps).map { i in
            let t = Double(i) / Double(steps)
            return CLLocationCoordinate2D(
                latitude: from.latitude + (to.latitude - from.latitude) * t,
                longitude: from.longitude + (to.longitude - from.longitude) * t
            )
        }
    }

    private static func trip(route: [CLLocationCoordinate2D]) -> Trip {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let points = route.enumerated().map { index, coordinate in
            TrackPoint(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitude: 0,
                speed: 20,
                timestamp: start.addingTimeInterval(Double(index) * 30)
            )
        }
        var trip = Trip(startDate: start, trackPoints: points)
        trip.endDate = start.addingTimeInterval(Double(route.count) * 30)
        trip.distance = 50_000
        trip.previewPolyline = Trip.encodePolyline(route)
        return trip
    }
}
