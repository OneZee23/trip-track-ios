import XCTest
import CoreLocation
@testable import TripTrack

/// History cards in filming mode show only the visible runs of the full trip.
/// The history keeps trips without points: TestFlight 101 had nothing to mask
/// and drew no route, Android 15 drew the whole one (5 Nov 2026).
final class FilmingCardRouteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Far from every demo seed, so a home zone left in the simulator cannot touch it.
    private func fullTrip() -> Trip {
        let points = (0..<40).map { index in
            TrackPoint(latitude: 60 + Double(index) * 0.001, longitude: 30, speed: 15, horizontalAccuracy: 5,
                       timestamp: start.addingTimeInterval(Double(index) * 10))
        }
        return Trip(startDate: start, endDate: points.last?.timestamp, distance: 4_300,
                    maxSpeed: 20, averageSpeed: 15, trackPoints: points, photos: [],
                    hiddenParts: TripHiddenParts(startMetres: 500, endMetres: 500, sections: [], numbersVisibleOnly: false),
                    title: "Trip", fuelUsed: 0, elevation: 0, region: nil, isPrivate: false, earnedBadgeIds: [])
    }

    func testAListedTripIsReadInFullAndShowsOnlyItsVisibleRuns() async throws {
        let full = fullTrip()
        var listed = full
        listed.trackPoints = []
        var asked = 0
        let route = await FilmingCardRoute.make(for: listed) { id in
            asked += 1
            return id == full.id ? full : nil
        }
        XCTAssertEqual(asked, 1)
        XCTAssertGreaterThan(route.points.count, 1)
        XCTAssertLessThan(route.points.count, full.trackPoints.count)
        let first = try XCTUnwrap(route.points.first), last = try XCTUnwrap(route.points.last)
        XCTAssertGreaterThan(first.latitude, full.trackPoints[0].latitude + 0.004)
        XCTAssertLessThan(last.latitude, full.trackPoints[39].latitude - 0.004)
    }

    func testATripThatCannotBeReadShowsNoRoute() async {
        var listed = fullTrip()
        listed.trackPoints = []
        let route = await FilmingCardRoute.make(for: listed) { _ in nil }
        XCTAssertTrue(route.points.isEmpty)
    }
}
