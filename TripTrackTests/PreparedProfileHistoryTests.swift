import XCTest
@testable import TripTrack

@MainActor
final class PreparedProfileHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return result
    }

    private func day(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func prepare(
        _ library: ProfileHistoryLibrary, journeys: [Journey] = [],
        query: String = "", from: Date? = nil, to: Date? = nil,
        language: LanguageManager.Language = .ru
    ) -> PreparedProfileHistory {
        PreparedProfileHistory(library: library, journeys: journeys, query: query,
                               from: from, to: to, language: language, calendar: calendar)
    }

    func testJourneyEditReplacesLegsAndMetadataWithoutLibraryReload() {
        let newest = Trip(startDate: day(15), title: "Newest")
        let oldest = Trip(startDate: day(13), title: "Oldest")
        let library = ProfileHistoryLibrary(trips: [newest, oldest])
        var journey = Journey(title: "Old title", startDate: day(12), endDate: day(16))
        let before = prepare(library, journeys: [journey])
        XCTAssertEqual(before.rows.count, 1)

        journey.title = "Edited title"
        journey.excludedTripIds = [newest.id]
        let after = prepare(library, journeys: [journey])
        XCTAssertEqual(after.rows.map(\.id), [newest.id, journey.id])
        guard case .journey(let updated, let legs) = after.rows[1] else {
            return XCTFail("The edited journey must remain a row")
        }
        XCTAssertEqual(updated.title, "Edited title")
        XCTAssertEqual(legs.map(\.id), [oldest.id])
        XCTAssertEqual(after.gridRuns.map { $0.map(\.id) }, [[newest.id], [journey.id]])

        journey.startDate = day(14)
        let narrowed = prepare(library, journeys: [journey])
        guard let narrowedRow = narrowed.rows.first(where: { $0.id == journey.id }),
              case .journey(_, let narrowedLegs) = narrowedRow else {
            return XCTFail("An emptied journey remains reachable")
        }
        XCTAssertTrue(narrowedLegs.isEmpty)
        XCTAssertEqual(prepare(library).rows.map(\.id), [newest.id, oldest.id],
                       "Deleting the journey must expose its legs again")
    }

    func testSameCountSameDatesReloadReplacesTripContentAndXP() throws {
        var trip = Trip(startDate: day(15), title: "Old title", region: "Berlin", xpEarned: 49)
        let before = prepare(ProfileHistoryLibrary(trips: [trip]))
        trip.title = "Renamed"
        trip.region = "Krasnodar Krai"
        trip.isPrivate = false
        trip.xpEarned = 150
        let after = prepare(ProfileHistoryLibrary(trips: [trip]), query: "краснодар")

        XCTAssertEqual(before.visibleTrips.count, after.visibleTrips.count)
        XCTAssertEqual(before.visibleTrips.first?.startDate, after.visibleTrips.first?.startDate)
        let updated = try XCTUnwrap(after.visibleTrips.first)
        XCTAssertEqual(updated.title, "Renamed")
        XCTAssertFalse(updated.isPrivate)
        XCTAssertEqual(after.historicalLevels?[trip.id], 3)
        XCTAssertEqual(before.historicalLevels?[trip.id], 1)
        guard let firstRow = after.rows.first, case .trip(let row) = firstRow else {
            return XCTFail("Updated trip row missing")
        }
        XCTAssertEqual(row.title, "Renamed")
        XCTAssertFalse(row.isPrivate)
    }

    func testSearchDateAndLanguageReprepareTheSameLibrary() {
        let latest = Trip(startDate: day(26), title: "Café", region: "Krasnodar Krai")
        let target = Trip(startDate: day(25, hour: 23), title: "Café", region: "Krasnodar Krai")
        let another = Trip(startDate: day(25), title: "Work", region: "Berlin")
        let library = ProfileHistoryLibrary(trips: [latest, target, another])

        let combined = prepare(library, query: "CAFE", from: day(25), to: nil)
        XCTAssertEqual(combined.visibleTrips.map(\.id), [target.id],
                       "The repeated autumn hour belongs to the selected local day")
        let russian = prepare(library, query: "краснодар")
        XCTAssertEqual(russian.visibleTrips.map(\.id), [latest.id, target.id])
        XCTAssertTrue(prepare(library, query: "краснодар", language: .en).visibleTrips.isEmpty)
        XCTAssertEqual(prepare(library, query: "  \n ").visibleTrips.map(\.id), library.trips.map(\.id))
        XCTAssertEqual(prepare(library, from: day(25), to: day(26)).visibleTrips.count, 3)
    }

    func testSearchUnfoldsMatchingLegAndClearingItRestoresJourneyRuns() {
        let newest = Trip(startDate: day(15), title: "Coffee")
        let oldest = Trip(startDate: day(13), title: "Mountains")
        let library = ProfileHistoryLibrary(trips: [newest, oldest])
        let journey = Journey(startDate: day(12), endDate: day(16))
        let folded = prepare(library, journeys: [journey])
        XCTAssertEqual(folded.rows.map(\.id), [journey.id])
        let searched = prepare(library, journeys: [journey], query: "mountains")
        XCTAssertEqual(searched.rows.map(\.id), [oldest.id])
        XCTAssertEqual(searched.gridRuns.map { $0.map(\.id) }, [[oldest.id]])
        XCTAssertEqual(prepare(library, journeys: [journey], query: " ").rows.map(\.id), [journey.id])
    }

    func testHistoricalXPUsesWholeLibraryThroughSearchCalendarAndJourneyFolding() {
        let newest = Trip(startDate: day(20), title: "Target", xpEarned: 200)
        let middle = Trip(startDate: day(15), title: "Middle", xpEarned: 100)
        let oldest = Trip(startDate: day(10), title: "Oldest", xpEarned: 60)
        let library = ProfileHistoryLibrary(trips: [newest, middle, oldest])
        let journey = Journey(startDate: day(9), endDate: day(16))
        let filtered = prepare(library, journeys: [journey], query: "target", from: day(20))
        XCTAssertEqual(filtered.rows.map(\.id), [newest.id])
        XCTAssertEqual(filtered.historicalLevels?[newest.id], 4)
        XCTAssertEqual(filtered.historicalLevels?[oldest.id], 2)
        XCTAssertEqual(prepare(library, journeys: [journey]).historicalLevels, filtered.historicalLevels)
    }

    func testUnknownHistoricalXPAndEmptyLibraryStayUnknown() {
        XCTAssertNil(prepare(ProfileHistoryLibrary(trips: [Trip(title: "Legacy")])).historicalLevels)
        XCTAssertNil(PreparedProfileHistory.empty.historicalLevels)
        XCTAssertTrue(PreparedProfileHistory.empty.rows.isEmpty)
        XCTAssertTrue(PreparedProfileHistory.empty.gridRuns.isEmpty)
    }

    func testLongRunsPreserveEveryRowAndJourneyBoundary() {
        let trips = (0..<1_000).map { Trip(startDate: day(1).addingTimeInterval(Double($0))) }
        let journey = Journey(startDate: day(1), endDate: day(2))
        let rows = trips.prefix(500).map(HistoryRow.trip)
            + [.journey(journey, legs: [])]
            + trips.suffix(500).map(HistoryRow.trip)
        let runs = HistoryFolding.runs(rows)
        XCTAssertEqual(runs.map(\.count), [500, 1, 500])
        XCTAssertEqual(runs.flatMap { $0 }.map(\.id), rows.map(\.id))
        XCTAssertTrue(HistoryFolding.runs([]).isEmpty)
    }
}
