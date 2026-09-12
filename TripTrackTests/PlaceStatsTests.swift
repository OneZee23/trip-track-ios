import XCTest
@testable import TripTrack

/// «Обычно занимает» — медиана по проездам ОДНОГО направления (±45° по курсу):
/// до Джубги «туда» — 2:14, «обратно» от неё — другое число и другая строка.
final class PlaceStatsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let placeId = UUID()

    private func pass(daysAgo: Double, course: Double, elapsed: TimeInterval) -> PlacePass {
        PlacePass(placeId: placeId, tripId: UUID(), timestamp: now.addingTimeInterval(-daysAgo * 86_400),
                  elapsedFromStart: elapsed, distanceFromStart: 143_000, course: course)
    }

    private func hms(_ h: Int, _ m: Int, _ s: Int = 0) -> TimeInterval { TimeInterval(h * 3600 + m * 60 + s) }

    func testDirectionsSplitAtFortyFiveDegrees() {
        let passes = [
            pass(daysAgo: 1, course: 0,   elapsed: hms(2, 14)),
            pass(daysAgo: 8, course: 5,   elapsed: hms(2, 8)),
            pass(daysAgo: 15, course: 350, elapsed: hms(2, 31)),
            pass(daysAgo: 2, course: 180, elapsed: hms(1, 58)),
            pass(daysAgo: 9, course: 175, elapsed: hms(1, 49)),
        ]
        let stats = PlaceStats.build(from: passes, now: now)
        XCTAssertEqual(stats.passCount, 5)
        XCTAssertEqual(stats.directions.count, 2)
        let north = stats.directions[0], south = stats.directions[1]   // по числу проездов
        XCTAssertEqual(north.count, 3)
        XCTAssertEqual(north.median, hms(2, 14))
        XCTAssertEqual(north.best, hms(2, 8))
        XCTAssertEqual(north.worst, hms(2, 31))
        XCTAssertEqual(south.count, 2)
        XCTAssertEqual(south.median, hms(1, 53, 30))                  // чётное — среднее двух средних
        XCTAssertEqual(PlaceStats.angularDistance(north.course, 0), 0, accuracy: 4)
        XCTAssertEqual(PlaceStats.angularDistance(south.course, 180), 0, accuracy: 4)
    }

    func testUnknownCourseCountsButHasNoDirection() {
        let passes = [pass(daysAgo: 1, course: PlacePass.unknownCourse, elapsed: hms(2, 0)),
                      pass(daysAgo: 2, course: 90, elapsed: hms(2, 5))]
        let stats = PlaceStats.build(from: passes, now: now)
        XCTAssertEqual(stats.passCount, 2)
        XCTAssertEqual(stats.directions.count, 1)
        XCTAssertEqual(stats.directions[0].count, 1)
    }

    func testFirstAndLastAndFirstTime() {
        let one = PlaceStats.build(from: [pass(daysAgo: 3, course: 0, elapsed: 100)], now: now)
        XCTAssertTrue(one.isFirstTime)
        XCTAssertEqual(one.firstAt, one.lastAt)
        let two = PlaceStats.build(from: [pass(daysAgo: 30, course: 0, elapsed: 100),
                                          pass(daysAgo: 3, course: 0, elapsed: 100)], now: now)
        XCTAssertFalse(two.isFirstTime)
        XCTAssertEqual(two.firstAt, now.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(two.lastAt, now.addingTimeInterval(-3 * 86_400))
        XCTAssertNil(PlaceStats.build(from: [], now: now).firstAt)
    }

    /// «Частый гость» — ≥ 5 проездов за 90 дней. Старые проезды не в счёт.
    func testFrequentGuestNeedsFiveInNinetyDays() {
        let fresh = (0..<5).map { pass(daysAgo: Double($0 * 10 + 1), course: 0, elapsed: 100) }
        XCTAssertTrue(PlaceStats.build(from: fresh, now: now).isFrequentGuest)
        XCTAssertFalse(PlaceStats.build(from: Array(fresh.prefix(4)), now: now).isFrequentGuest)
        let stale = (0..<5).map { pass(daysAgo: Double(100 + $0), course: 0, elapsed: 100) }
        XCTAssertFalse(PlaceStats.build(from: stale, now: now).isFrequentGuest)
    }

    func testAngularDistanceWrapsAround() {
        XCTAssertEqual(PlaceStats.angularDistance(350, 10), 20)
        XCTAssertEqual(PlaceStats.angularDistance(10, 350), 20)
        XCTAssertEqual(PlaceStats.angularDistance(0, 180), 180)
    }
}
