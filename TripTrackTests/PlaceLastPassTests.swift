import XCTest
import CoreLocation
@testable import TripTrack

/// «Дача · вчера · на 7 мин быстрее обычного» — и четыре границы, ради
/// которых эта строка вообще имеет смысл (спека «Места v2» §3.6).
///
/// Вся ценность здесь в том, чтобы находка оставалась РЕДКОЙ. Строка без
/// порогов появлялась бы после каждой поездки и за неделю превратилась бы в
/// шум, который человек перестаёт читать, — поэтому пороги проверяются
/// числом, а не открытым экраном.
final class PlaceLastPassTests: XCTestCase {

    private let place = UUID()

    private func pass(_ minutesAgo: Int, elapsed: TimeInterval,
                      course: Double = 90) -> PlacePass {
        let when = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        return PlacePass(id: UUID(), placeId: place, tripId: UUID(),
                         timestamp: when, elapsedFromStart: elapsed,
                         distanceFromStart: 1_000, course: course)
    }

    // MARK: Что показывается

    /// Медиана трёх прежних проездов — 60 мин, последний 50: на 10 минут
    /// быстрее, и это больше обоих порогов.
    func testAFasterPassIsReported() {
        let passes = [pass(0, elapsed: 50 * 60),
                      pass(60 * 24, elapsed: 58 * 60),
                      pass(60 * 48, elapsed: 60 * 60),
                      pass(60 * 72, elapsed: 62 * 60)]
        let reading = PlaceLastPass.reading(placeId: place, passes: passes)
        XCTAssertNotNil(reading)
        XCTAssertTrue(reading?.isFaster == true)
        XCTAssertEqual(reading?.delta ?? 0, 10 * 60, accuracy: 1)
    }

    /// «Дольше обычного» — такой же законный ответ, а не молчание.
    func testASlowerPassIsReportedToo() {
        let passes = [pass(0, elapsed: 75 * 60),
                      pass(60 * 24, elapsed: 58 * 60),
                      pass(60 * 48, elapsed: 60 * 60),
                      pass(60 * 72, elapsed: 62 * 60)]
        let reading = PlaceLastPass.reading(placeId: place, passes: passes)
        XCTAssertTrue(reading?.isFaster == false)
        XCTAssertEqual(reading?.delta ?? 0, 15 * 60, accuracy: 1)
    }

    // MARK: Границы

    /// Медиана значима ТОЛЬКО от трёх проездов в этом направлении, и сам
    /// последний в счёт не идёт: иначе он сравнивался бы сам с собой.
    func testTwoPassesAreNotEnoughForAMedian() {
        let passes = [pass(0, elapsed: 30 * 60), pass(60 * 24, elapsed: 60 * 60)]
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: passes),
                     "одного прежнего проезда мало, чтобы называть его «обычным»")
    }

    /// Меньше пяти минут — не находка, сколько бы процентов это ни было.
    func testATinyDeltaIsSilentEvenIfItIsABigShare() {
        // Медиана 10 мин, последний 7 — это 30 %, но всего три минуты.
        let passes = [pass(0, elapsed: 7 * 60),
                      pass(60 * 24, elapsed: 10 * 60),
                      pass(60 * 48, elapsed: 10 * 60),
                      pass(60 * 72, elapsed: 10 * 60)]
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: passes))
    }

    /// И наоборот: пять минут от трёхчасовой дороги — это шум, а не находка.
    func testAFiveMinuteDeltaOnALongDriveIsSilent() {
        let passes = [pass(0, elapsed: 175 * 60),
                      pass(60 * 24, elapsed: 180 * 60),
                      pass(60 * 48, elapsed: 180 * 60),
                      pass(60 * 72, elapsed: 180 * 60)]
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: passes),
                     "пять минут от трёх часов — это меньше десятой доли")
    }

    /// Сравнение идёт ВНУТРИ направления. Дорога «туда» и дорога «обратно»
    /// занимают разное время, и смешав их, мы сравнивали бы поездку на работу
    /// с поездкой домой.
    func testTheOppositeDirectionIsNotUsedForComparison() {
        let passes = [pass(0, elapsed: 50 * 60, course: 90),
                      pass(60 * 24, elapsed: 20 * 60, course: 270),
                      pass(60 * 48, elapsed: 20 * 60, course: 270),
                      pass(60 * 72, elapsed: 20 * 60, course: 270)]
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: passes),
                     "обратные проезды — не «как обычно» для проезда туда")
    }

    /// У проезда без курса направления нет, и сравнивать его не с чем:
    /// взять все проезды подряд значило бы смешать туда и обратно.
    func testAPassWithoutACourseIsSilent() {
        let passes = [pass(0, elapsed: 50 * 60, course: PlacePass.unknownCourse),
                      pass(60 * 24, elapsed: 60 * 60),
                      pass(60 * 48, elapsed: 60 * 60),
                      pass(60 * 72, elapsed: 60 * 60)]
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: passes))
    }

    func testAPlaceWithNoPassesIsSilent() {
        XCTAssertNil(PlaceLastPass.reading(placeId: place, passes: []))
    }

    /// Проезды приходят в любом порядке — последним считается САМЫЙ СВЕЖИЙ
    /// по времени, а не последний в массиве.
    func testTheLatestPassWinsRegardlessOfArrayOrder() {
        let passes = [pass(60 * 48, elapsed: 60 * 60),
                      pass(0, elapsed: 50 * 60),
                      pass(60 * 72, elapsed: 62 * 60),
                      pass(60 * 24, elapsed: 58 * 60)]
        let reading = PlaceLastPass.reading(placeId: place, passes: passes)
        XCTAssertTrue(reading?.isFaster == true)
        XCTAssertEqual(reading?.delta ?? 0, 10 * 60, accuracy: 1)
    }
}
