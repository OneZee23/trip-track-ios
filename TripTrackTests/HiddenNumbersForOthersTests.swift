import XCTest
@testable import TripTrack

/// «Другие увидят …» under «Цифры для других» prints the numbers that upload
/// under the current choice. TestFlight 101 always printed the visible-only
/// numbers, and «Вся поездка» promised 1.6 km for a 2.6 km trip (5 Nov 2026).
final class HiddenNumbersForOthersTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func trip() -> Trip {
        let points = (0...30).map { index in
            TrackPoint(latitude: 45, longitude: 39 + Double(index) * 0.001, speed: 12,
                       horizontalAccuracy: 5, timestamp: start.addingTimeInterval(Double(index) * 60))
        }
        return Trip(startDate: start, endDate: points.last?.timestamp.addingTimeInterval(45), distance: 2_600,
                    maxSpeed: 20, averageSpeed: 10, trackPoints: points, photos: [],
                    hiddenParts: TripHiddenParts(startMetres: 500, endMetres: 500, sections: [], numbersVisibleOnly: false),
                    title: "Trip", fuelUsed: 0, elevation: 0, region: nil, isPrivate: false, earnedBadgeIds: [])
    }

    private func visibleRuns(_ trip: Trip) -> [[TrackPoint]] {
        HiddenPartsResolver.resolve(points: trip.trackPoints, recordingBreaks: [],
                                    startMetres: 500, endMetres: 500, sections: []).visibleRuns
    }

    func testWholeTripPromisesTheWholeTrip() {
        let trip = trip()
        let numbers = HiddenPartsEditorModel.numbersForOthers(trip: trip, visibleRuns: visibleRuns(trip), visibleOnly: false)
        XCTAssertEqual(numbers.metres, 2_600)
        XCTAssertEqual(numbers.seconds, trip.duration)
    }

    func testVisiblePartsPromiseWhatUploads() throws {
        let trip = trip()
        let runs = visibleRuns(trip)
        let numbers = HiddenPartsEditorModel.numbersForOthers(trip: trip, visibleRuns: runs, visibleOnly: true)
        let uploaded = TripSyncPayload.visibleMetrics(runs)
        let first = try XCTUnwrap(uploaded.startDate), last = try XCTUnwrap(uploaded.endDate)
        XCTAssertEqual(numbers.metres, uploaded.distance)
        XCTAssertEqual(numbers.seconds, last.timeIntervalSince(first))
        XCTAssertLessThan(numbers.metres, trip.distance)
        XCTAssertLessThan(numbers.seconds, trip.duration)
    }

    func testEverythingHiddenPromisesNothing() {
        let numbers = HiddenPartsEditorModel.numbersForOthers(trip: trip(), visibleRuns: [], visibleOnly: true)
        XCTAssertEqual(numbers.metres, 0)
        XCTAssertEqual(numbers.seconds, 0)
    }
}
