import XCTest
@testable import TripTrack

/// История сегмента считается по проездам двух мест, а не хранится — см.
/// доккомент `SegmentHistory`.
final class SegmentHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)
    private let fromPlace = UUID()
    private let toPlace = UUID()

    private func pass(_ place: UUID, tripId: UUID, elapsed: TimeInterval) -> PlacePass {
        PlacePass(placeId: place, tripId: tripId, timestamp: start.addingTimeInterval(elapsed),
                  elapsedFromStart: elapsed, distanceFromStart: elapsed * 20, course: 0)
    }

    private func hms(_ h: Int, _ m: Int, _ s: Int = 0) -> TimeInterval { TimeInterval(h * 3600 + m * 60 + s) }

    func testThreeTripsGiveThreeTimesAscending() {
        let tripA = UUID(), tripB = UUID(), tripC = UUID()
        let fromPasses = [
            pass(fromPlace, tripId: tripA, elapsed: 1_000),
            pass(fromPlace, tripId: tripB, elapsed: 2_000),
            pass(fromPlace, tripId: tripC, elapsed: 500),
        ]
        let toPasses = [
            pass(toPlace, tripId: tripA, elapsed: 1_000 + hms(5, 12)),
            pass(toPlace, tripId: tripB, elapsed: 2_000 + hms(4, 58)),
            pass(toPlace, tripId: tripC, elapsed: 500 + hms(5, 40)),
        ]
        let times = SegmentHistory.times(fromPasses: fromPasses, toPasses: toPasses)
        XCTAssertEqual(times, [hms(4, 58), hms(5, 12), hms(5, 40)])
    }

    /// Поездка, где проехали в обратную сторону (`to` раньше `from`), в
    /// истории отрезка не отвечает ни на что — не считается.
    func testTripWhereToPrecedesFromIsExcluded() {
        let trip = UUID()
        let fromPasses = [pass(fromPlace, tripId: trip, elapsed: 5_000)]
        let toPasses = [pass(toPlace, tripId: trip, elapsed: 1_000)]
        XCTAssertEqual(SegmentHistory.times(fromPasses: fromPasses, toPasses: toPasses), [])
    }

    /// «Туда и обратно»: дорога проходит `from`, затем `to`, разворачивается
    /// у тупика за `to` и проходит оба места ещё раз в обратном порядке —
    /// четыре прохода в одной поездке, а результат один: минимальная
    /// положительная разница (прямой заезд), а не четыре комбинации.
    func testThereAndBackWithinOneTripGivesOneMinimalDelta() {
        let trip = UUID()
        let fromPasses = [
            pass(fromPlace, tripId: trip, elapsed: 1_000),          // туда
            pass(fromPlace, tripId: trip, elapsed: 2_000),          // обратно
        ]
        let toPasses = [
            pass(toPlace, tripId: trip, elapsed: 1_000 + hms(0, 5)),   // туда, +5 мин
            pass(toPlace, tripId: trip, elapsed: 2_000 - hms(0, 5)),   // обратно, раньше на 5 мин
        ]
        // Прямых (положительных) пар две: обе дают 5 минут — минимум однозначен.
        XCTAssertEqual(SegmentHistory.times(fromPasses: fromPasses, toPasses: toPasses), [hms(0, 5)])
    }

    func testClockFormatsHoursAndMinutes() {
        XCTAssertEqual(SegmentHistory.clock(17_880), "4:58")
        XCTAssertEqual(SegmentHistory.clock(42 * 60), "0:42")
        XCTAssertEqual(SegmentHistory.clock(hms(12, 5)), "12:05")
    }

    /// Неполная минута отбрасывается, а не округляется вверх, — так же, как
    /// её отбрасывают `Trip.formattedTimeHuman` и `CheckpointReading.clock`.
    func testClockDropsIncompleteMinute() {
        XCTAssertEqual(SegmentHistory.clock(90), "0:01")
        XCTAssertEqual(SegmentHistory.clock(59), "0:00")
        XCTAssertEqual(SegmentHistory.clock(hms(1, 0) - 1), "0:59")
    }
}
