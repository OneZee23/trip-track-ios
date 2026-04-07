import XCTest
import CoreLocation
@testable import TripTrack

final class GeometryUtilsTests: XCTestCase {

    // MARK: - Haversine Distance

    func testHaversineDistance_samePoint() {
        let coord = CLLocationCoordinate2D(latitude: 55.75, longitude: 37.62)
        let dist = GeometryUtils.haversineDistance(coord, coord)
        XCTAssertEqual(dist, 0, accuracy: 0.01)
    }

    func testHaversineDistance_knownCities() {
        let moscow = CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)
        let spb = CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351)
        let dist = GeometryUtils.haversineDistance(moscow, spb)
        // Moscow-SPb ~ 634 km
        XCTAssertEqual(dist, 634_000, accuracy: 10_000)
    }

    func testHaversineDistance_shortDistance() {
        let a = CLLocationCoordinate2D(latitude: 45.0350, longitude: 38.9750)
        let b = CLLocationCoordinate2D(latitude: 45.0360, longitude: 38.9760)
        let dist = GeometryUtils.haversineDistance(a, b)
        // ~130m diagonal
        XCTAssertGreaterThan(dist, 100)
        XCTAssertLessThan(dist, 200)
    }

    // MARK: - Split By Gaps

    func testSplitByGaps_noGaps() {
        let coords = [
            CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            CLLocationCoordinate2D(latitude: 45.036, longitude: 38.976),
            CLLocationCoordinate2D(latitude: 45.037, longitude: 38.977),
        ]
        let segments = GeometryUtils.splitByGaps(coords, threshold: 1_000)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.count, 3)
    }

    func testSplitByGaps_withGap() {
        let coords = [
            CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            CLLocationCoordinate2D(latitude: 45.036, longitude: 38.976),
            // ~200 km gap
            CLLocationCoordinate2D(latitude: 47.000, longitude: 39.000),
            CLLocationCoordinate2D(latitude: 47.001, longitude: 39.001),
        ]
        let segments = GeometryUtils.splitByGaps(coords, threshold: 1_000)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].count, 2)
        XCTAssertEqual(segments[1].count, 2)
    }

    func testSplitByGaps_singlePoint() {
        let coords = [CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0)]
        let segments = GeometryUtils.splitByGaps(coords, threshold: 1_000)
        XCTAssertTrue(segments.isEmpty)
    }

    func testSplitByGaps_allGaps() {
        // Each point > 1km from the next, no segment has 2+ points
        let coords = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 46.0, longitude: 39.0),
            CLLocationCoordinate2D(latitude: 47.0, longitude: 40.0),
        ]
        let segments = GeometryUtils.splitByGaps(coords, threshold: 1_000)
        XCTAssertTrue(segments.isEmpty)
    }

    func testDefaultGapThreshold() {
        XCTAssertEqual(GeometryUtils.defaultGapThreshold, 1_000)
    }

    // MARK: - RDP Simplification

    func testSimplifyRDP_straightLine() {
        // Points on a straight line should simplify to just start and end
        let coords = (0..<10).map {
            CLLocationCoordinate2D(latitude: 45.0 + Double($0) * 0.001, longitude: 38.0)
        }
        let simplified = GeometryUtils.simplifyRDP(coords, epsilon: 0.0001)
        XCTAssertEqual(simplified.count, 2)
    }

    func testSimplifyRDP_preservesCurve() {
        // L-shaped path — middle point should be preserved
        let coords = [
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.0),
            CLLocationCoordinate2D(latitude: 45.0, longitude: 38.01),
            CLLocationCoordinate2D(latitude: 45.01, longitude: 38.01),
        ]
        let simplified = GeometryUtils.simplifyRDP(coords, epsilon: 0.0001)
        XCTAssertEqual(simplified.count, 3)
    }
}
