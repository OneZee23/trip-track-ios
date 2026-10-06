import XCTest
@testable import TripTrack

@MainActor
final class TripHistoryFilterTests: XCTestCase {
    func testTextSearchIsLocalCaseAndDiacriticInsensitiveAndPreservesOrder() {
        let first = Trip(title: "Café у моря", region: "Krasnodar")
        let second = Trip(title: "Горы", region: "Krasnodar")
        XCTAssertEqual(search([first, second], "  CAFE   МОРЯ ").map(\.id), [first.id])
        XCTAssertEqual(search([first, second], "KRASNODAR").map(\.id), [first.id, second.id])
        XCTAssertTrue(search([first, second], "Москва").isEmpty)
        XCTAssertEqual(search([first, second], " \n ").map(\.id), [first.id, second.id])
    }

    func testDateAndQueryIntersectAndIncludeWholeLocalDayAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let trips = [Trip(startDate: date(24, 23), title: "Home"),
                     Trip(startDate: date(25, 0), title: "Home"),
                     Trip(startDate: date(25, 23), title: "Home"),
                     Trip(startDate: date(25, 12), title: "Work"),
                     Trip(startDate: date(26, 0), title: "Home")]
        let matched = TripHistoryFilter.apply(trips, query: "home", from: date(25, 12),
                                             to: nil, language: .en, calendar: calendar)
        XCTAssertEqual(matched.map(\.id), [trips[1].id, trips[2].id])
    }

    func testZeroDistanceTripIsStillInCalendarResults() {
        let day = Date()
        let trip = Trip(startDate: day, distance: 0, title: "Walk to car")
        XCTAssertEqual(TripHistoryFilter.apply([trip], query: "", from: day, to: day,
                                               language: .en).map(\.id), [trip.id])
    }

    private func search(_ trips: [Trip], _ text: String) -> [Trip] {
        TripHistoryFilter.apply(trips, query: text, from: nil, to: nil, language: .ru)
    }
}
