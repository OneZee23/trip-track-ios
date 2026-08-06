import XCTest
@testable import TripTrack

/// `TripAutoTitle` owns the «5 авг, 17:41» auto-title canon: generation in
/// the APP language and re-rendering of legacy titles that were stamped with
/// the recording device's system locale («5 Aug, 17:41» inside a RU app).
final class TripAutoTitleTests: XCTestCase {
    // Fixed date: 5 Aug 2026, 17:41 local.
    private var date: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 5; c.hour = 17; c.minute = 41
        return Calendar.current.date(from: c)!
    }

    func testGenerateRussianIsDotless() {
        XCTAssertEqual(TripAutoTitle.generate(for: date, language: .ru), "5 авг, 17:41")
    }

    func testGenerateEnglish() {
        XCTAssertEqual(TripAutoTitle.generate(for: date, language: .en), "5 Aug, 17:41")
    }

    func testGenerateNilDateFallsBack() {
        XCTAssertEqual(TripAutoTitle.generate(for: nil, language: .ru), "Поездка")
        XCTAssertEqual(TripAutoTitle.generate(for: nil, language: .en), "Trip")
    }

    func testLegacyEnglishTitleRerendersInRussian() {
        XCTAssertEqual(
            TripAutoTitle.localized("5 Aug, 17:41", startDate: date, language: .ru),
            "5 авг, 17:41"
        )
    }

    func testRussianTitleRerendersInEnglish() {
        XCTAssertEqual(
            TripAutoTitle.localized("5 авг, 17:41", startDate: date, language: .en),
            "5 Aug, 17:41"
        )
    }

    func testDottedLegacyRussianTitleRerenders() {
        XCTAssertEqual(
            TripAutoTitle.localized("5 авг., 17:41", startDate: date, language: .ru),
            "5 авг, 17:41"
        )
    }

    func testUserTitleUntouched() {
        XCTAssertEqual(
            TripAutoTitle.localized("Москва — Тверь и обратно", startDate: date, language: .ru),
            "Москва — Тверь и обратно"
        )
    }

    func testDateLikeUserTitleForDifferentDayUntouched() {
        // A date-formatted title that does NOT match this trip's start date
        // is user content, not an auto-title.
        XCTAssertEqual(
            TripAutoTitle.localized("6 Aug, 12:00", startDate: date, language: .ru),
            "6 Aug, 12:00"
        )
    }

    func testNilAndEmptyPassThrough() {
        XCTAssertNil(TripAutoTitle.localized(nil, startDate: date, language: .ru))
        XCTAssertEqual(TripAutoTitle.localized("", startDate: date, language: .ru), "")
    }
}
