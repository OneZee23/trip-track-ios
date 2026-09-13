import XCTest
@testable import TripTrack

/// Плитки экрана места «первый раз»/«последний»: год печатается только
/// когда просмотр приходится на ДРУГОЙ календарный год, чем сама дата —
/// иначе стоянка трёхлетней давности читалась бы как «в этом году». `now`
/// фиксирован в каждом тесте, а не `Date()`: иначе тест решал бы, в каком
/// году его запускают, а не то, что решает код.
final class PlaceTileDateTests: XCTestCase {
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testSameCalendarYearOmitsTheYear() {
        let now = date(2026, 7, 1)
        let firstAt = date(2026, 6, 18)
        let s = PlaceDetailView.tileDate(firstAt, now: now, calendar: calendar, lang: .en)
        XCTAssertFalse(s.contains("2026"), "same-year date must not print a four-digit year: \(s)")
    }

    func testDifferentCalendarYearKeepsTheYear() {
        let now = date(2026, 7, 1)
        let lastAt = date(2024, 6, 18)
        let s = PlaceDetailView.tileDate(lastAt, now: now, calendar: calendar, lang: .en)
        XCTAssertTrue(s.contains("2024"), "a different-year date must keep the year: \(s)")
    }
}
