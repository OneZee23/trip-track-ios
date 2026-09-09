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

    func testJourneyWithoutLegsInTheRangeIsHidden() {
        let september = [trip(day: 20), trip(day: 9)]
        // Фильтр календаря отрезал все плечи: показывать пустую карточку не о чем.
        let august = Journey(
            startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 1))!,
            endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10))!)

        let rows = HistoryFolding.fold(trips: september, journeys: [august])

        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy { if case .trip = $0 { return true } else { return false } })
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
