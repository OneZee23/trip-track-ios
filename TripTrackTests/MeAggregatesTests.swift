import XCTest
@testable import TripTrack

/// Unit tests for the Я-tab aggregates (§3 of the 6.1.0 Me-tab plan):
/// year scoping incl. Dec 31 / Jan 1 boundary trips, year-streak runs,
/// first-visit «Новый регион» logic, and empty-input safety.
final class MeAggregatesTests: XCTestCase {

    private let cal = Calendar.current

    /// Fixed "now": June 15 of the current year, midday — keeps fixtures
    /// deterministic regardless of when the suite runs.
    private var now: Date {
        let year = cal.component(.year, from: Date())
        return cal.date(from: DateComponents(year: year, month: 6, day: 15, hour: 12))!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 10) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func trip(
        start: Date,
        km: Double = 10,
        hours: Double = 1,
        region: String? = nil,
        title: String? = nil
    ) -> Trip {
        Trip(
            startDate: start,
            endDate: start.addingTimeInterval(hours * 3600),
            distance: km * 1000,
            title: title,
            region: region
        )
    }

    // MARK: - Empty input

    func testEmptyInputIsSafe() {
        let a = MeAggregates.compute(trips: [], now: now, calendar: cal)
        XCTAssertEqual(a.tripCount, 0)
        XCTAssertEqual(a.totalKm, 0)
        XCTAssertEqual(a.yearTripCount, 0)
        XCTAssertEqual(a.regionsAllTime, 0)
        XCTAssertEqual(a.yearStreak, 0)
        XCTAssertEqual(a.monthlyKm, [Double](repeating: 0, count: 12))
        XCTAssertNil(a.yearAgoTrip)
        XCTAssertNil(a.longestYearTrip)
        XCTAssertNil(a.newRegion)
        XCTAssertNil(a.topRegion)
        XCTAssertTrue(a.recentTrips.isEmpty)
        XCTAssertEqual(a.year, cal.component(.year, from: now))
    }

    // MARK: - Year scoping (Dec 31 / Jan 1 boundary)

    func testYearScopingIncludesJan1AndDec31OfCurrentYearOnly() {
        let year = cal.component(.year, from: now)
        let jan1 = trip(start: date(year: year, month: 1, day: 1, hour: 0), km: 100)
        let dec31 = trip(start: date(year: year, month: 12, day: 31, hour: 23), km: 50)
        let prevDec31 = trip(start: date(year: year - 1, month: 12, day: 31, hour: 23), km: 999)
        let nextJan1 = trip(start: date(year: year + 1, month: 1, day: 1, hour: 0), km: 777)

        let a = MeAggregates.compute(
            trips: [jan1, dec31, prevDec31, nextJan1],
            now: now, calendar: cal
        )

        XCTAssertEqual(a.yearTripCount, 2)
        XCTAssertEqual(a.yearKm, 150, accuracy: 0.001)
        // All-time totals still count everything.
        XCTAssertEqual(a.tripCount, 4)
        XCTAssertEqual(a.totalKm, 1926, accuracy: 0.001)
        // Monthly buckets: Jan gets 100, Dec gets 50 — boundary trips of
        // OTHER years never leak into the chart.
        XCTAssertEqual(a.monthlyKm[0], 100, accuracy: 0.001)
        XCTAssertEqual(a.monthlyKm[11], 50, accuracy: 0.001)
        XCTAssertEqual(a.monthlyKm[1...10].reduce(0, +), 0, accuracy: 0.001)
        // Longest year trip is the 100 km one — the 999 km trip is last year.
        XCTAssertEqual(a.longestYearTrip?.distanceKm ?? 0, 100, accuracy: 0.001)
        // All-time longest IS the 999 km one.
        XCTAssertEqual(a.longestTripKm, 999, accuracy: 0.001)
    }

    // MARK: - Year streak

    func testYearStreakCountsLongestConsecutiveRun() {
        let year = cal.component(.year, from: now)
        // 3-day run in March, 2-day run in May, singleton in June.
        let trips = [
            trip(start: date(year: year, month: 3, day: 1)),
            trip(start: date(year: year, month: 3, day: 2)),
            trip(start: date(year: year, month: 3, day: 3)),
            trip(start: date(year: year, month: 5, day: 10)),
            trip(start: date(year: year, month: 5, day: 11)),
            trip(start: date(year: year, month: 6, day: 1)),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertEqual(a.yearStreak, 3)
    }

    func testYearStreakIgnoresMultipleTripsSameDay() {
        let year = cal.component(.year, from: now)
        let trips = [
            trip(start: date(year: year, month: 4, day: 1, hour: 8)),
            trip(start: date(year: year, month: 4, day: 1, hour: 20)),
            trip(start: date(year: year, month: 4, day: 2)),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertEqual(a.yearStreak, 2)
    }

    func testSingleTripYearStreakIsOne() {
        let year = cal.component(.year, from: now)
        let a = MeAggregates.compute(
            trips: [trip(start: date(year: year, month: 2, day: 5))],
            now: now, calendar: cal
        )
        XCTAssertEqual(a.yearStreak, 1)
    }

    func testLongestStreakHelperEmptyIsZero() {
        XCTAssertEqual(MeAggregates.longestStreak(days: [], calendar: cal), 0)
    }

    // MARK: - «Новый регион» first-visit logic

    func testNewRegionRequiresAtLeastTwoAllTimeRegions() {
        let year = cal.component(.year, from: now)
        // Single region, first visited this year — NOT "new" (lone-region
        // user's only region isn't a discovery).
        let a = MeAggregates.compute(
            trips: [trip(start: date(year: year, month: 3, day: 1), region: "Тверская обл.")],
            now: now, calendar: cal
        )
        XCTAssertNil(a.newRegion)
    }

    func testNewRegionPicksMostRecentFirstVisitOfThisYear() {
        let year = cal.component(.year, from: now)
        let trips = [
            // Old home region, visited for years.
            trip(start: date(year: year - 2, month: 5, day: 1), region: "Московская обл."),
            trip(start: date(year: year, month: 1, day: 10), region: "Московская обл."),
            // First visited in February this year.
            trip(start: date(year: year, month: 2, day: 1), region: "Тверская обл."),
            // First visited in April this year — the most recent discovery.
            trip(start: date(year: year, month: 4, day: 1), region: "Ярославская обл."),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertEqual(a.newRegion, "Ярославская обл.")
    }

    func testRegionFirstVisitedLastYearIsNotNew() {
        let year = cal.component(.year, from: now)
        let trips = [
            trip(start: date(year: year - 1, month: 5, day: 1), region: "Московская обл."),
            // Visited again this year, but FIRST visit was last year.
            trip(start: date(year: year, month: 2, day: 1), region: "Тверская обл."),
            trip(start: date(year: year - 1, month: 11, day: 1), region: "Тверская обл."),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertNil(a.newRegion)
    }

    // MARK: - Moments / misc

    func testYearAgoTripPicksBestWithinThreeDayWindow() {
        let target = cal.date(byAdding: .year, value: -1, to: now)!
        let near = trip(start: cal.date(byAdding: .day, value: 1, to: target)!, km: 40)
        let nearer = trip(start: cal.date(byAdding: .day, value: -2, to: target)!, km: 90)
        let far = trip(start: cal.date(byAdding: .day, value: 10, to: target)!, km: 500)
        let a = MeAggregates.compute(trips: [near, nearer, far], now: now, calendar: cal)
        XCTAssertEqual(a.yearAgoTrip?.distanceKm ?? 0, 90, accuracy: 0.001)
    }

    func testTopRegionByTripCount() {
        let year = cal.component(.year, from: now)
        let trips = [
            trip(start: date(year: year, month: 1, day: 1), region: "A"),
            trip(start: date(year: year, month: 1, day: 2), region: "B"),
            trip(start: date(year: year, month: 1, day: 3), region: "B"),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertEqual(a.topRegion, "B")
    }

    func testRecentTripsCapAtTenNewestFirst() {
        let year = cal.component(.year, from: now)
        let trips = (1...15).map { day in
            trip(start: date(year: year, month: 3, day: day), km: Double(day))
        }
        let a = MeAggregates.compute(trips: trips.shuffled(), now: now, calendar: cal)
        XCTAssertEqual(a.recentTrips.count, 10)
        // Newest first: March 15 down to March 6.
        XCTAssertEqual(a.recentTrips.first?.distanceKm ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(a.recentTrips.last?.distanceKm ?? 0, 6, accuracy: 0.001)
    }

    func testMaxDayAggregates() {
        let year = cal.component(.year, from: now)
        let trips = [
            // Two trips in one day: 60 km / 5 h total.
            trip(start: date(year: year, month: 2, day: 1, hour: 8), km: 25, hours: 2),
            trip(start: date(year: year, month: 2, day: 1, hour: 14), km: 35, hours: 3),
            // Single bigger trip another day: 50 km / 4 h.
            trip(start: date(year: year, month: 2, day: 3), km: 50, hours: 4),
        ]
        let a = MeAggregates.compute(trips: trips, now: now, calendar: cal)
        XCTAssertEqual(a.maxDayKm, 60, accuracy: 0.001)
        XCTAssertEqual(a.maxDayDuration, 5 * 3600, accuracy: 1)
    }
}
