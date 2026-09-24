import XCTest
import CoreLocation
@testable import TripTrack

final class GapFillTests: XCTestCase {
    private func gap(north: Double, seconds: Double) -> TrackGapFinder.Gap {
        let a = TrackTestKit.coordinate(east: 0, north: 0)
        let b = TrackTestKit.coordinate(east: 0, north: north)
        return .init(
            from: .init(latitude: a.latitude, longitude: a.longitude,
                        timestamp: TrackTestKit.epoch, isInterpolated: false),
            to: .init(latitude: b.latitude, longitude: b.longitude,
                      timestamp: TrackTestKit.epoch.addingTimeInterval(seconds), isInterpolated: false))
    }

    func testResampleLiesStrictlyInsideTheGap() {
        let g = gap(north: 800, seconds: 60)
        let path = [TrackTestKit.coordinate(east: 0, north: 0), TrackTestKit.coordinate(east: 0, north: 800)]
        let pts = GapFill.resample(path, from: g.from.timestamp, to: g.to.timestamp,
                                   altitudeFrom: 10, altitudeTo: 50)
        XCTAssertEqual(pts.count, 39)
        XCTAssertTrue(pts.allSatisfy { $0.isInterpolated && $0.speed == -1 && $0.horizontalAccuracy == -1 })
        XCTAssertTrue(pts.allSatisfy { $0.timestamp > g.from.timestamp && $0.timestamp < g.to.timestamp })
        XCTAssertEqual(pts.map(\.timestamp), pts.map(\.timestamp).sorted())
        XCTAssertTrue(pts.allSatisfy { $0.altitude > 10 && $0.altitude < 50 })
    }

    func testResampleIsCapped() {
        let path = [TrackTestKit.coordinate(east: 0, north: 0), TrackTestKit.coordinate(east: 0, north: 50_000)]
        let pts = GapFill.resample(path, from: TrackTestKit.epoch,
                                   to: TrackTestKit.epoch.addingTimeInterval(2400),
                                   altitudeFrom: 0, altitudeTo: 0)
        XCTAssertEqual(pts.count, GapFill.maxPoints)
    }

    /// Review Focus 1: прыжок GPS не достраивается.
    func testTeleportIsNotFillable() {
        XCTAssertFalse(GapFill.isFillable(gap(north: 5000, seconds: 10)))
        XCTAssertTrue(GapFill.isFillable(gap(north: 800, seconds: 60)))
    }

    func testPlausibilityTable() {
        XCTAssertTrue(GapFill.isPlausible(routeMetres: 2400, routeSeconds: 150, straightMetres: 1000, gapSeconds: 120))
        XCTAssertFalse(GapFill.isPlausible(routeMetres: 2600, routeSeconds: 150, straightMetres: 1000, gapSeconds: 120))
        // Короткая дыра: потолок времени — дыра + 5 минут.
        XCTAssertTrue(GapFill.isPlausible(routeMetres: 1200, routeSeconds: 300, straightMetres: 1000, gapSeconds: 20))
        XCTAssertFalse(GapFill.isPlausible(routeMetres: 1200, routeSeconds: 700, straightMetres: 1000, gapSeconds: 60))
    }

    func testStraightnessTellsAStraightFillFromARoad() {
        let a = TrackTestKit.coordinate(east: 0, north: 0)
        let b = TrackTestKit.coordinate(east: 0, north: 800)
        let straight = GapFill.resample([a, b], from: TrackTestKit.epoch,
                                        to: TrackTestKit.epoch.addingTimeInterval(60),
                                        altitudeFrom: 0, altitudeTo: 0).map(\.coordinate)
        XCTAssertTrue(GapFill.isStraight(straight, from: a, to: b))
        XCTAssertTrue(GapFill.isStraight([], from: a, to: b), "пустая дыра — тоже «ещё не дорога»")
        XCTAssertFalse(GapFill.isStraight([TrackTestKit.coordinate(east: 200, north: 400)], from: a, to: b))
    }
}
