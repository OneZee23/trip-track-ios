import XCTest
import CoreLocation
@testable import TripTrack

/// The fog of roads is the map's whole idea, and every bug it has had so far
/// was invisible in the data and obvious on screen: sixty stacked traces of
/// one commute, a stroke floor that turned streets into blobs, a motorway
/// counted as one 150 m cell. These lock down the properties that make it
/// look right, so the next change has to break something loudly.
final class RoadFogTests: XCTestCase {

    // MARK: - Helpers

    /// A straight run between two coordinates with `points` vertices, nudged
    /// by a few metres of GPS-like wander that differs per pass.
    private func route(
        from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D,
        points: Int = 24, pass: Int = 0, wanderDegrees: Double = 0.00008
    ) -> (id: UUID, coordinates: [CLLocationCoordinate2D]) {
        let coords = (0..<points).map { i -> CLLocationCoordinate2D in
            let t = Double(i) / Double(points - 1)
            let phase = Double(i) * 0.6 + Double(pass) * 1.7
            return CLLocationCoordinate2D(
                latitude: a.latitude + (b.latitude - a.latitude) * t
                    + sin(phase) * wanderDegrees,
                longitude: a.longitude + (b.longitude - a.longitude) * t
                    + cos(phase * 1.3) * wanderDegrees
            )
        }
        return (UUID(), coords)
    }

    private func build(
        _ trips: [(id: UUID, coordinates: [CLLocationCoordinate2D])]
    ) -> RoadFog {
        RoadFog.build(trips: trips) { _ in 0 }
    }

    private func vertexCount(_ fog: RoadFog) -> Int {
        fog.tiers.flatMap(\.runs).reduce(0) { $0 + $1.count }
    }

    /// Which ramp band a coordinate's road ended up in, by finding the run
    /// that passes closest to it.
    private func tier(of fog: RoadFog, near target: CLLocationCoordinate2D) -> Int? {
        var best: (index: Int, distance: Double)?
        for (index, tier) in fog.tiers.enumerated() {
            for run in tier.runs {
                for point in run {
                    let d = abs(point.latitude - target.latitude)
                        + abs(point.longitude - target.longitude)
                    if best == nil || d < best!.distance { best = (index, d) }
                }
            }
        }
        return best?.index
    }

    // MARK: - Deduplication

    /// The bug that started all of this: one road driven twenty times drew
    /// twenty traces of it. The network has to grow with the roads opened,
    /// not with how often they were driven.
    func testRepeatedRoadCollapsesIntoOneNetwork() {
        let a = CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00)
        let b = CLLocationCoordinate2D(latitude: 45.06, longitude: 39.07)

        let once = build([route(from: a, to: b, pass: 0)])
        let twenty = build((0..<20).map { route(from: a, to: b, pass: $0) })

        XCTAssertGreaterThan(vertexCount(once), 20, "a 9 km road is more than a few vertices")
        XCTAssertLessThan(
            vertexCount(twenty), vertexCount(once) * 2,
            "twenty drives over one road must not draw twenty roads"
        )
    }

    /// Preview polylines are RDP-simplified, so a motorway leg can be one
    /// segment kilometres long. Deciding to keep or drop geometry a whole
    /// segment at a time let one fresh cell keep an entire motorway — which
    /// is how five parallel ribbons of the same commute reached the screen.
    func testRepeatsCollapseEvenWhenSegmentsAreKilometresLong() {
        let a = CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00)
        let b = CLLocationCoordinate2D(latitude: 45.30, longitude: 39.40)

        // Four vertices over 45 km: legs of ~15 km, exactly the shape RDP
        // leaves behind on a straight road.
        let once = build([route(from: a, to: b, points: 4, pass: 0)])
        let ten = build((0..<10).map { route(from: a, to: b, points: 4, pass: $0) })

        XCTAssertLessThan(vertexCount(ten), vertexCount(once) * 2)
    }

    // MARK: - Heat

    func testRoadDrivenOftenBurnsHotterThanRoadDrivenOnce() {
        let hotStart = CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00)
        let hotEnd = CLLocationCoordinate2D(latitude: 45.04, longitude: 39.05)
        let coldStart = CLLocationCoordinate2D(latitude: 45.50, longitude: 39.50)
        let coldEnd = CLLocationCoordinate2D(latitude: 45.54, longitude: 39.55)

        var trips = (0..<12).map { route(from: hotStart, to: hotEnd, pass: $0) }
        trips.append(route(from: coldStart, to: coldEnd))
        let fog = build(trips)

        guard let hot = tier(of: fog, near: hotStart),
              let cold = tier(of: fog, near: coldStart) else {
            return XCTFail("both roads must be drawn")
        }
        XCTAssertGreaterThan(hot, cold, "the road you drive daily has to outshine the one-off")
    }

    /// City streets run north-south and east-west, so plenty of them sit on
    /// top of a grid line. Counting heat on the containing cell alone split
    /// those passes between the two sides, and a road driven six times came
    /// out looking like a road driven three.
    func testRoadOnACellBoundaryCountsTheSameAsRoadInsideACell() {
        // Exactly on a grid line, and running along it.
        let gridLatitude = (45.0 / RoadFog.cellDegrees).rounded() * RoadFog.cellDegrees
        let onEdgeStart = CLLocationCoordinate2D(latitude: gridLatitude, longitude: 39.00)
        let onEdgeEnd = CLLocationCoordinate2D(latitude: gridLatitude, longitude: 39.05)
        // Half a cell north of a grid line, elsewhere on the map.
        let insideLatitude = gridLatitude + RoadFog.cellDegrees / 2 + 0.5
        let insideStart = CLLocationCoordinate2D(latitude: insideLatitude, longitude: 39.00)
        let insideEnd = CLLocationCoordinate2D(latitude: insideLatitude, longitude: 39.05)

        var trips: [(id: UUID, coordinates: [CLLocationCoordinate2D])] = []
        for pass in 0..<6 {
            trips.append(route(from: onEdgeStart, to: onEdgeEnd, pass: pass))
            trips.append(route(from: insideStart, to: insideEnd, pass: pass))
        }
        let fog = build(trips)

        XCTAssertEqual(
            tier(of: fog, near: onEdgeStart), tier(of: fog, near: insideStart),
            "the same six drives must read the same whether or not the road hugs a grid line"
        )
    }

    /// Someone whose every road was driven exactly once still has a map to
    /// look at — a pure ranking would put all of it at the dead bottom of the
    /// ramp.
    func testNetworkWithNoRepeatsIsStillLit() {
        let fog = build((0..<5).map { i in
            route(
                from: CLLocationCoordinate2D(latitude: 45.0 + Double(i), longitude: 39.0),
                to: CLLocationCoordinate2D(latitude: 45.04 + Double(i), longitude: 39.05)
            )
        })
        XCTAssertEqual(fog.maxPasses, 1)
        XCTAssertEqual(fog.tiers.count, 1, "nothing repeated means nothing to rank")
        let intensity = try? XCTUnwrap(fog.tiers.first?.intensity)
        XCTAssertGreaterThan(intensity ?? 0, 0.4, "a single band must sit in the visible middle")
    }

    /// The ramp is normalised against the data's own distribution, so a
    /// spread of pass counts has to reach more than two colours.
    func testSpreadOfPassCountsUsesSeveralBands() {
        var trips: [(id: UUID, coordinates: [CLLocationCoordinate2D])] = []
        for (index, repeats) in [1, 2, 5, 12, 30].enumerated() {
            let base = 45.0 + Double(index)
            for pass in 0..<repeats {
                trips.append(route(
                    from: CLLocationCoordinate2D(latitude: base, longitude: 39.0),
                    to: CLLocationCoordinate2D(latitude: base + 0.04, longitude: 39.05),
                    pass: pass
                ))
            }
        }
        let fog = build(trips)
        XCTAssertGreaterThanOrEqual(fog.tiers.count, 3,
                                    "five very different roads must not collapse to two colours")
        XCTAssertEqual(fog.maxPasses, 30)
    }

    // MARK: - Opened road

    /// «Дороги края» counts cells, and a straight motorway arrives as ONE
    /// segment. Attributing it to the cell under its midpoint counted 10 km
    /// of road as 150 m — the bar read 1% for a region crossed end to end.
    func testStraightMotorwayOpensEveryCellItCrosses() {
        // 0.09° of latitude ≈ 10 km, given as two points and nothing else.
        let trip = (UUID(), [
            CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00),
            CLLocationCoordinate2D(latitude: 45.09, longitude: 39.00),
        ])
        let fog = RoadFog.build(trips: [trip]) { _ in 7 }

        let expected = 0.09 / RoadFog.cellDegrees   // ≈ 67 cells
        let opened = Double(fog.openedCellsByRegion[7] ?? 0)
        XCTAssertGreaterThan(opened, expected * 0.8, "a 10 km leg is not one cell of road")
        XCTAssertLessThan(opened, expected * 1.2)
    }

    func testDrivingTheSameRoadAgainOpensNoNewRoad() {
        let a = CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00)
        let b = CLLocationCoordinate2D(latitude: 45.04, longitude: 39.05)
        let once = RoadFog.build(trips: [route(from: a, to: b, pass: 0)]) { _ in 1 }
        let eight = RoadFog.build(trips: (0..<8).map { route(from: a, to: b, pass: $0) }) { _ in 1 }

        let first = Double(once.openedCellsByRegion[1] ?? 0)
        let repeated = Double(eight.openedCellsByRegion[1] ?? 0)
        XCTAssertGreaterThan(first, 10)
        XCTAssertLessThan(repeated, first * 1.5, "opened road grows by going somewhere new, not by going again")
    }

    // MARK: - Rubbish in

    /// A paused recording leaves a straight line across a country between two
    /// real stretches. Lighting it would claim a road that was never driven.
    func testTeleportGapIsNotDrawn() {
        let trip = (UUID(), [
            CLLocationCoordinate2D(latitude: 45.00, longitude: 39.00),
            CLLocationCoordinate2D(latitude: 45.02, longitude: 39.02),
            // 500 km away.
            CLLocationCoordinate2D(latitude: 49.50, longitude: 39.02),
            CLLocationCoordinate2D(latitude: 49.52, longitude: 39.04),
        ])
        let fog = build([trip])

        let drawn = fog.tiers.flatMap(\.runs).flatMap { $0 }
        XCTAssertFalse(drawn.isEmpty, "the real stretches still get drawn")
        XCTAssertFalse(
            drawn.contains { $0.latitude > 45.2 && $0.latitude < 49.3 },
            "nothing may be drawn along the jump"
        )
    }

    func testEmptyInputProducesNothing() {
        XCTAssertTrue(build([]).isEmpty)
        XCTAssertTrue(build([(UUID(), [])]).isEmpty)
        XCTAssertTrue(build([(UUID(), [CLLocationCoordinate2D(latitude: 45, longitude: 39)])]).isEmpty)
    }

    // MARK: - Scale

    /// The map is rebuilt on every data change, off the main actor but in
    /// front of a spinner. This is the size where it used to hurt.
    func testBuildStaysFastOnAHeavyLibrary() {
        var trips: [(id: UUID, coordinates: [CLLocationCoordinate2D])] = []
        for index in 0..<300 {
            let base = 44.0 + Double(index % 60) * 0.02
            let lon = 38.0 + Double(index / 60) * 0.02
            trips.append(route(
                from: CLLocationCoordinate2D(latitude: base, longitude: lon),
                to: CLLocationCoordinate2D(latitude: base + 0.25, longitude: lon + 0.3),
                points: 250, pass: index
            ))
        }

        let started = Date()
        let fog = build(trips)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertFalse(fog.isEmpty)
        // Generous on purpose — this is a guard against an accidental O(n²),
        // not a benchmark. Debug builds on a simulator are the slow case.
        XCTAssertLessThan(elapsed, 10, "300 trips × 250 points took \(elapsed)s to collapse")
    }
}
