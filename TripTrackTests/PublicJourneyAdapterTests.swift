import XCTest
import CoreLocation
@testable import TripTrack

/// Coverage for `TripTrack/Models/Social/PublicJourneyAdapter.swift`:
/// `Trip(publicLeg:)` and `JourneyWindow.days`. `Journey(publicJourney:
/// ownerId:)` / `Journey(socialHead:)` are exercised by the compiler (every
/// field is passed through a plain memberwise call) — no dedicated test,
/// to keep this task's count at the brief's specified 1272 + 5.
final class PublicJourneyAdapterTests: XCTestCase {

    /// Fixed UTC calendar — `JourneyWindow.days` defaults to `.current`,
    /// which would make these tests depend on the machine's time zone.
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: hour))!
    }

    // MARK: - Trip(publicLeg:)

    /// `endDate` falls back to `startDate + duration` when the server sent
    /// none, and `averageSpeed` is `distance / duration` — same derivation
    /// `Trip(social:)` uses, so the two adapters never disagree.
    func testPublicLegDerivesEndDateAndAverageSpeed() {
        let start = day(2026, 9, 13, hour: 10)
        let leg = PublicJourneyLeg(
            id: UUID(), startDate: start, endDate: nil,
            distance: 480_000, duration: 7_200, region: "Краснодарский край", previewPolyline: nil)
        let trip = Trip(publicLeg: leg)
        XCTAssertEqual(trip.endDate, start.addingTimeInterval(7_200))
        XCTAssertEqual(trip.averageSpeed, 480_000.0 / 7_200.0, accuracy: 0.0001)
    }

    func testPublicLegPreviewCoordinatesDecodeFromValidBase64() {
        let coords = [
            CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975),
            CLLocationCoordinate2D(latitude: 43.585, longitude: 39.723),
        ]
        let polyline = Trip.encodePolyline(coords).base64EncodedString()
        let leg = PublicJourneyLeg(
            id: UUID(), startDate: day(2026, 9, 13), endDate: nil,
            distance: 100_000, duration: 3_600, region: nil, previewPolyline: polyline)
        let trip = Trip(publicLeg: leg)
        XCTAssertEqual(trip.previewCoordinates.count, 2)
        XCTAssertEqual(trip.previewCoordinates.first?.latitude ?? 0, 45.035, accuracy: 0.001)
    }

    // MARK: - JourneyWindow.days

    /// Closed window 12–17 сен → 6 (calendar-day inclusive); open window
    /// with `now` 14 сен, start 12 сен → 3; `endDate < startDate` clamps to
    /// 1 rather than crashing or going negative.
    func testDaysCoversClosedOpenAndInvertedWindows() {
        XCTAssertEqual(
            JourneyWindow.days(startDate: day(2026, 9, 12), endDate: day(2026, 9, 17),
                                now: day(2026, 9, 20), calendar: utc),
            6)
        XCTAssertEqual(
            JourneyWindow.days(startDate: day(2026, 9, 12), endDate: nil,
                                now: day(2026, 9, 14), calendar: utc),
            3)
        XCTAssertEqual(
            JourneyWindow.days(startDate: day(2026, 9, 17), endDate: day(2026, 9, 12),
                                now: day(2026, 9, 20), calendar: utc),
            1)
    }
}
