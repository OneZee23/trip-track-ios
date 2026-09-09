import XCTest
@testable import TripTrack

/// Схлопывание плеч в «Моих»: шесть записей о дороге в Тбилиси должны стоять
/// в истории ОДНОЙ карточкой — и ровно там, где стояло бы её последнее плечо.
final class ProfileHistoryFoldingTests: XCTestCase {
    private func date(_ day: Int, hour: Int = 10) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func trip(day: Int, hour: Int = 10) -> Trip {
        let start = date(day, hour: hour)
        return Trip(id: UUID(), startDate: start, endDate: start.addingTimeInterval(3_600),
                    distance: 120_000, maxSpeed: 30, averageSpeed: 25,
                    trackPoints: [], photos: [], title: nil, fuelUsed: 0, elevation: 0,
                    region: nil, isPrivate: true, earnedBadgeIds: [], xpEarned: 0)
    }

    func testLegsCollapseIntoOneRowAtTheJourneysPlace() {
        let t20 = trip(day: 20)
        let t15 = trip(day: 15)
        let t13 = trip(day: 13)
        let t9 = trip(day: 9)
        let journey = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23))

        let rows = HistoryFolding.fold(trips: [t20, t15, t13, t9], journeys: [journey])

        XCTAssertEqual(rows.count, 3, "два плеча ушли внутрь путешествия")
        guard case .trip(let first) = rows[0] else { return XCTFail("первой — поездка 20 сентября") }
        XCTAssertEqual(first.id, t20.id)
        guard case .journey(let j, let legs) = rows[1] else { return XCTFail("путешествие стоит вторым") }
        XCTAssertEqual(j.id, journey.id)
        XCTAssertEqual(legs.map(\.id), [t15.id, t13.id], "плечи внутри — от новых к старым")
        guard case .trip(let last) = rows[2] else { return XCTFail("последней — поездка 9 сентября") }
        XCTAssertEqual(last.id, t9.id)
    }

    func testJourneyOutsideTheCalendarRangeIsHidden() {
        let september = [trip(day: 20), trip(day: 9)]
        // Фильтр календаря отрезал август целиком — вместе с окном: карточка
        // висела бы в сентябре пустой, не про то, что человек смотрит.
        let august = Journey(
            startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!,
            endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!)

        let rows = HistoryFolding.fold(
            trips: september, journeys: [august],
            range: HistoryFolding.dayRange(from: date(1), to: date(30)))

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { if case .trip = $0 { return true } else { return false } })
    }

    /// Плечи можно удалить все до одного — окно от этого не исчезает: даты оно
    /// продолжает занимать, и без карточки до него было бы не дойти.
    func testJourneyWithNoLegsAtAllIsShown() {
        let september = [trip(day: 20), trip(day: 9)]
        let emptied = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23))

        let rows = HistoryFolding.fold(trips: september, journeys: [emptied])

        XCTAssertEqual(rows.count, 3)
        // Стоит по началу окна: между 20-м и 9-м, а не в конце истории.
        guard case .journey(let j, let legs) = rows[1] else {
            return XCTFail("пустое путешествие — строка на своём месте по датам")
        }
        XCTAssertEqual(j.id, emptied.id)
        XCTAssertTrue(legs.isEmpty)
    }

    /// «По последнему плечу, а не по первому» — и это РАЗНЫЕ места в списке.
    ///
    /// Плечи 13 и 15 сентября, между ними чужая поездка 14-го. По последнему
    /// плечу карточка встаёт НАД ней, по первому — под: путешествие уезжало бы
    /// вниз ровно на столько дней, сколько длилось, а самая свежая история
    /// пряталась бы за поездками, которые случились раньше её конца.
    func testJourneySortsByItsLatestLegNotItsEarliest() {
        let t15 = trip(day: 15)
        let t14 = trip(day: 14)
        let t13 = trip(day: 13)
        // 14-е внутри окна по датам, но человек убрал его руками — значит это
        // ЧУЖАЯ поездка, и различить порядок она может.
        let journey = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23),
                              excludedTripIds: [t14.id])

        let rows = HistoryFolding.fold(trips: [t15, t14, t13], journeys: [journey])

        XCTAssertEqual(rows.count, 2)
        guard case .journey(let j, let legs) = rows[0] else {
            return XCTFail("путешествие стоит НАД поездкой 14-го — по своему последнему плечу")
        }
        XCTAssertEqual(j.id, journey.id)
        XCTAssertEqual(legs.map(\.id), [t15.id, t13.id])
        guard case .trip(let alien) = rows[1] else { return XCTFail("вторым — 14 сентября") }
        XCTAssertEqual(alien.id, t14.id)
    }

    /// Пустое окно и отрезок календаря: внутри — видно, снаружи — нет. Два
    /// случая одной строки `intersects`, и различить их может только отрезок.
    func testEmptyJourneyFollowsTheCalendarRange() {
        let september = [trip(day: 20), trip(day: 9)]
        let emptied = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23))

        let inside = HistoryFolding.fold(
            trips: september, journeys: [emptied],
            range: HistoryFolding.dayRange(from: date(12), to: date(16)))
        XCTAssertEqual(inside.count, 3, "окно внутри отрезка — карточка на месте")

        let outside = HistoryFolding.fold(
            trips: september, journeys: [emptied],
            range: HistoryFolding.dayRange(from: date(1), to: date(5)))
        XCTAssertEqual(outside.count, 2, "окно вне отрезка — карточки нет")
        XCTAssertTrue(outside.allSatisfy { if case .trip = $0 { return true } else { return false } })
    }

    /// Одна поездка не может лежать в двух путешествиях сразу. Локально это
    /// невозможно — окна не пересекаются по построению, — но приезжают они с
    /// сервера, где чужой клиент мог не проверить.
    func testOverlappingJourneysNeverShowATripTwice() {
        let t14 = trip(day: 14)
        let first = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23))
        let second = Journey(startDate: date(13, hour: 0), endDate: date(18, hour: 23))

        let rows = HistoryFolding.fold(trips: [t14], journeys: [first, second])

        XCTAssertEqual(rows.count, 2, "две карточки — но поездка внутри одна")
        let legIds = rows.flatMap { row -> [UUID] in
            if case .journey(_, let legs) = row { return legs.map(\.id) } else { return [] }
        }
        XCTAssertEqual(legIds, [t14.id], "во второе окно та же поездка не попадает")
    }

    /// Сетка рисуется кусками: подряд идущие поездки — одной решёткой,
    /// путешествие — во всю ширину между ними.
    func testRunsSplitTripsAroundJourneys() {
        let t20 = trip(day: 20)
        let t9 = trip(day: 9)
        let t8 = trip(day: 8)
        let journey = Journey(startDate: date(12, hour: 0), endDate: date(16, hour: 23))
        let rows = HistoryFolding.fold(trips: [t20, trip(day: 15), t9, t8], journeys: [journey])

        let runs = HistoryFolding.runs(rows)

        XCTAssertEqual(runs.map(\.count), [1, 1, 2])
        guard case .journey = runs[1][0] else { return XCTFail("путешествие — свой отдельный кусок") }
        XCTAssertEqual(runs[2].compactMap { if case .trip(let t) = $0 { return t.id } else { return nil } },
                       [t9.id, t8.id])
    }
}
