import XCTest
@testable import TripTrack

/// `RelativeTripDate.string(from:now:language:)` covers Strava-style
/// thresholds.
///
/// NOTE on testability: the implementation accepts a `now` parameter for
/// the seconds-elapsed math, but `Calendar.isDateInToday` /
/// `isDateInYesterday` ignore that injection — they always compare to
/// the system clock. So calendar-day bucket tests anchor to the real
/// `Date()`; only the under-an-hour buckets are fully deterministic.
final class RelativeTripDateTests: XCTestCase {

    /// Anchor for relative-seconds tests. Picked far from midnight in any
    /// common timezone so today/yesterday math is unambiguous.
    private var anchor: Date {
        // Today at 12:00 in the device timezone — guarantees "5 min ago"
        // is still the same calendar day.
        let cal = Calendar.current
        return cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - just-now bucket

    func testJustNowEnglish() {
        let date = anchor.addingTimeInterval(-30)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "just now")
    }

    func testJustNowRussian() {
        let date = anchor.addingTimeInterval(-30)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .ru), "только что")
    }

    func testZeroSecondsIsJustNow() {
        XCTAssertEqual(RelativeTripDate.string(from: anchor, now: anchor, language: .en), "just now")
    }

    func testFutureDateClampsToJustNow() {
        // secondsAgo is `max(0, ...)` so future dates fall in the just-now
        // bucket — defensive against clock skew when server timestamps
        // arrive a few seconds ahead of device time.
        let date = anchor.addingTimeInterval(60)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "just now")
    }

    // MARK: - minutes bucket (< 1 hour, today)

    func testOneMinuteAgoEnglish() {
        let date = anchor.addingTimeInterval(-60)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "1 min ago")
    }

    func testFiveMinutesAgoEnglish() {
        let date = anchor.addingTimeInterval(-5 * 60)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "5 min ago")
    }

    func testFiveMinutesAgoRussian() {
        let date = anchor.addingTimeInterval(-5 * 60)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .ru), "5 мин назад")
    }

    func testFiftyNineMinutesAgoEnglish() {
        let date = anchor.addingTimeInterval(-59 * 60)
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "59 min ago")
    }

    // MARK: - today bucket (≥ 1 hour, same calendar day)

    func testOneHourAgoStartsTodayBucket() {
        // anchor is today at noon. anchor - 1h = today at 11:00. Same calendar
        // day → "Today at 11:00".
        let date = anchor.addingTimeInterval(-3600)
        let result = RelativeTripDate.string(from: date, now: anchor, language: .en)
        XCTAssertTrue(result.hasPrefix("Today at"), "Expected Today prefix, got: \(result)")
    }

    func testTodayBucketRussianPrefix() {
        let date = anchor.addingTimeInterval(-3600)
        let result = RelativeTripDate.string(from: date, now: anchor, language: .ru)
        XCTAssertTrue(result.hasPrefix("Сегодня в"), "Expected Сегодня prefix, got: \(result)")
    }

    // MARK: - yesterday bucket

    func testYesterdayBucketEnglishPrefix() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        let result = RelativeTripDate.string(from: yesterday, now: anchor, language: .en)
        XCTAssertTrue(result.hasPrefix("Yesterday at"), "Expected Yesterday prefix, got: \(result)")
    }

    func testYesterdayBucketRussianPrefix() {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        let result = RelativeTripDate.string(from: yesterday, now: anchor, language: .ru)
        XCTAssertTrue(result.hasPrefix("Вчера в"), "Expected Вчера prefix, got: \(result)")
    }

    // MARK: - days-ago bucket (2-6)

    func testTwoDaysAgoEnglish() {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -2, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "2 days ago")
    }

    func testTwoDaysAgoRussianPlural() {
        // 2 → "дня" (genitive singular form for 2-4)
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -2, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .ru), "2 дня назад")
    }

    func testSixDaysAgoEnglish() {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -6, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        XCTAssertEqual(RelativeTripDate.string(from: date, now: anchor, language: .en), "6 days ago")
    }

    // MARK: - absolute-date bucket (≥ 7 days)

    func testSevenDaysAgoFallsToAbsoluteDate() {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -7, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        let result = RelativeTripDate.string(from: date, now: anchor, language: .en)
        XCTAssertFalse(result.contains("days ago"))
        XCTAssertFalse(result.contains("Today"))
        XCTAssertFalse(result.contains("Yesterday"))
        XCTAssertTrue(result.contains(where: \.isNumber))
    }

    func testDifferentYearIncludesYear() {
        // 400+ days back guarantees a year change.
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .day, value: -400, to: anchor) else {
            return XCTFail("Calendar arithmetic failed")
        }
        let result = RelativeTripDate.string(from: date, now: anchor, language: .en)
        let year = calendar.component(.year, from: date)
        XCTAssertTrue(result.contains(String(year)), "Expected year \(year) in result, got: \(result)")
    }
}
