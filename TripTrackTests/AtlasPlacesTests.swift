import XCTest
import CoreLocation
@testable import TripTrack

/// Места на карте «Атласа» под выбранным периодом (макет S8).
final class AtlasPlacesTests: XCTestCase {

    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return c
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    private func seed(_ name: String, _ dates: [Date]) -> AtlasPlaces.Seed {
        AtlasPlaces.Seed(id: UUID(), coordinate: CLLocationCoordinate2D(latitude: 45, longitude: 39),
                         name: name, usual: 600, passDates: dates)
    }

    /// Окно смотрит на ПРОЕЗДЫ, а не на диапазон «первый…последний»: место,
    /// где были в январе и в декабре, не становится июньским оттого, что июнь
    /// лежит между этими датами.
    func testAPlaceVisitedAroundTheWindowIsNotInIt() {
        let s = seed("Дача", [day(2026, 1, 10), day(2026, 12, 20)])
        let pins = AtlasPlaces.build(seeds: [s],
                                     period: .custom(start: day(2026, 6, 1), end: day(2026, 6, 30)),
                                     now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.first?.inPeriod, false)
    }

    func testAPassInsideTheWindowPutsThePlaceInPeriod() {
        let s = seed("Пляж", [day(2026, 1, 10), day(2026, 6, 15)])
        let pins = AtlasPlaces.build(seeds: [s],
                                     period: .custom(start: day(2026, 6, 1), end: day(2026, 6, 30)),
                                     now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.first?.inPeriod, true)
        XCTAssertEqual(pins.first?.lastAt, day(2026, 6, 15),
                       "под булавкой в периоде — дата ВНУТРИ него, а не снаружи")
    }

    /// Место вне окна подписывается собственной датой: «когда я тут был» —
    /// вопрос про место, и пустой ответ был бы хуже честного.
    func testAPlaceOutOfPeriodKeepsItsOwnDate() {
        let s = seed("Дача", [day(2026, 1, 10)])
        let pins = AtlasPlaces.build(seeds: [s],
                                     period: .custom(start: day(2026, 6, 1), end: day(2026, 6, 30)),
                                     now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.first?.lastAt, day(2026, 1, 10))
        XCTAssertEqual(pins.first?.passCount, 1, "счёт проездов период не режет")
    }

    func testWithoutAPeriodEveryPlaceIsInIt() {
        let pins = AtlasPlaces.build(seeds: [seed("A", [day(2020, 1, 1)]), seed("B", [day(2026, 9, 1)])],
                                     period: .allTime, now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.filter(\.inPeriod).count, 2)
        XCTAssertEqual(AtlasPlaces.inPeriodCount(pins), 2)
    }

    func testNewestFirst() {
        let pins = AtlasPlaces.build(seeds: [seed("Старое", [day(2020, 1, 1)]),
                                             seed("Свежее", [day(2026, 9, 1)])],
                                     period: .allTime, now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.map(\.name), ["Свежее", "Старое"])
    }

    func testPlaceWithoutPassesSurvives() {
        let pins = AtlasPlaces.build(seeds: [seed("Пустое", [])], period: .allTime,
                                     now: day(2026, 12, 31), calendar: calendar)
        XCTAssertEqual(pins.count, 1)
        XCTAssertNil(pins.first?.lastAt)
        XCTAssertEqual(pins.first?.passCount, 0)
    }
}
