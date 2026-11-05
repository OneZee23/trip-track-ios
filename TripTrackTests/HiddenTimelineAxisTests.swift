import XCTest
@testable import TripTrack

/// The editor's trip bar puts speed colours, hidden hatch and section handles
/// on one time axis. TestFlight 101 placed colours by point number and hatch
/// by time, and the hidden start of the owner's trip sat a quarter of the way
/// along the bar (5 Nov 2026).
final class HiddenTimelineAxisTests: XCTestCase {
    private let tripStart = Date(timeIntervalSince1970: 1_800_000_000)

    /// The first fix arrives 80 s after the trip starts. Points are dense while
    /// crawling out of the yard and sparse on the open road.
    private func unevenPoints() -> [TrackPoint] {
        var points: [TrackPoint] = []
        var time = tripStart.addingTimeInterval(80)
        var longitude = 39.0
        for _ in 0..<60 {
            points.append(TrackPoint(latitude: 45, longitude: longitude, speed: 2, timestamp: time))
            time += 1
            longitude += 0.00003
        }
        for _ in 0..<40 {
            points.append(TrackPoint(latitude: 45, longitude: longitude, speed: 15, timestamp: time))
            time += 10
            longitude += 0.0019
        }
        return points
    }

    func testHiddenEdgesReachBothEndsOfTheBarWhenTheFirstFixIsLate() throws {
        let points = unevenPoints()
        let axis = HiddenTimelineAxis(points: points, tripStart: tripStart,
                                      tripEnd: points.last!.timestamp.addingTimeInterval(30))
        let resolution = HiddenPartsResolver.resolve(points: points, recordingBreaks: [],
                                                     startMetres: 500, endMetres: 500, sections: [])
        let start = try XCTUnwrap(resolution.hiddenRanges.first)
        let end = try XCTUnwrap(resolution.hiddenRanges.last)
        XCTAssertEqual(axis.fraction(of: start.from), 0)
        XCTAssertEqual(axis.fraction(of: end.to), 1)
    }

    func testColoursSitWhereTheirTimeIsAndNotWhereTheirNumberIs() {
        let points = unevenPoints()
        let axis = HiddenTimelineAxis(points: points, tripStart: tripStart, tripEnd: nil)
        // 60 of 100 points, but one minute of seven and a half.
        XCTAssertEqual(axis.fraction(of: points[60].timestamp), 60.0 / 450.0, accuracy: 0.0001)
    }

    func testLabelsAreTheFirstAndLastPointsAndFallBackToTheTrip() {
        let points = unevenPoints()
        let axis = HiddenTimelineAxis(points: points, tripStart: tripStart, tripEnd: nil)
        XCTAssertEqual(axis.start, points.first!.timestamp)
        XCTAssertEqual(axis.end, points.last!.timestamp)
        let empty = HiddenTimelineAxis(points: [], tripStart: tripStart, tripEnd: tripStart.addingTimeInterval(600))
        XCTAssertEqual(empty.start, tripStart)
        XCTAssertEqual(empty.end, tripStart.addingTimeInterval(600))
        XCTAssertEqual(empty.fraction(of: tripStart.addingTimeInterval(150)), 0.25, accuracy: 0.0001)
    }

    func testDateAtFractionInvertsTheAxisAndClamps() {
        let points = unevenPoints()
        let axis = HiddenTimelineAxis(points: points, tripStart: tripStart, tripEnd: nil)
        let middle = axis.date(atFraction: 0.5)
        XCTAssertEqual(axis.fraction(of: middle), 0.5, accuracy: 0.0001)
        XCTAssertEqual(axis.date(atFraction: -1), axis.start)
        XCTAssertEqual(axis.date(atFraction: 2), axis.end)
    }

    func testHandlesSnapToTheNearestPointInTime() {
        let points = unevenPoints()
        let early = points.first!.timestamp.addingTimeInterval(-30)
        let late = points.last!.timestamp.addingTimeInterval(30)
        XCTAssertEqual(HiddenTimelineAxis.nearestTimestamp(to: early, in: points), points.first!.timestamp)
        XCTAssertEqual(HiddenTimelineAxis.nearestTimestamp(to: late, in: points), points.last!.timestamp)
        // Sparse part: points 10 s apart; 3 s after one is nearer to it.
        XCTAssertEqual(HiddenTimelineAxis.nearestTimestamp(to: points[70].timestamp.addingTimeInterval(3), in: points),
                       points[70].timestamp)
        XCTAssertEqual(HiddenTimelineAxis.nearestTimestamp(to: points[70].timestamp.addingTimeInterval(7), in: points),
                       points[71].timestamp)
        XCTAssertEqual(HiddenTimelineAxis.nearestTimestamp(to: points[42].timestamp, in: points), points[42].timestamp)
        XCTAssertNil(HiddenTimelineAxis.nearestTimestamp(to: early, in: []))
    }
}
