import XCTest
@testable import TripTrack

/// v0.5.7: night / early-morning badges must be awarded when the trip OVERLAPS the
/// window at any point, not only by its start hour (an overnight 20:00→07:00 drive
/// previously missed "Ночной гонщик").
final class BadgeNightWindowTests: XCTestCase {
    private func dc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> DateComponents {
        DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
    }

    private func trip(start: DateComponents, durationHours: Double) -> Trip {
        let startDate = Calendar.current.date(from: start)!
        return Trip(startDate: startDate,
                    endDate: startDate.addingTimeInterval(durationHours * 3600),
                    distance: 50_000)
    }

    func testOvernightTripEarnsNightBadge() {
        // 20:00 → 07:00 next day overlaps the 22:00–05:00 window.
        let t = trip(start: dc(2026, 6, 10, 20), durationHours: 11)
        XCTAssertTrue(BadgeManager.computeStats(from: [t]).hasNightTrip)
    }

    func testEveningRunningPastMidnightEarnsNight() {
        // 21:00 + 3h → crosses 22:00 and midnight.
        let t = trip(start: dc(2026, 6, 10, 21), durationHours: 3)
        XCTAssertTrue(BadgeManager.computeStats(from: [t]).hasNightTrip)
    }

    func testDaytimeTripDoesNotEarnNight() {
        // 10:00 → 13:00, no overlap with 22:00–05:00.
        let t = trip(start: dc(2026, 6, 10, 10), durationHours: 3)
        XCTAssertFalse(BadgeManager.computeStats(from: [t]).hasNightTrip)
    }

    func testOvernightTripEarnsEarlyMorning() {
        // 20:00 → 07:00 overlaps the 00:00–06:00 window.
        let t = trip(start: dc(2026, 6, 10, 20), durationHours: 11)
        XCTAssertTrue(BadgeManager.computeStats(from: [t]).hasEarlyMorningTrip)
    }
}
