import XCTest
import CoreLocation
@testable import TripTrack

final class ProfileMonthlyJournalTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
    private func trip(_ day: Int, month: Int = 10, reversed: Bool = false) -> Trip {
        let points = [GeohashEncoder.centerCoordinate(of: "ucftjk"), GeohashEncoder.centerCoordinate(of: "ucftm1")]
        return Trip(startDate: date(day, month: month), endDate: date(day, month: month).addingTimeInterval(600),
                    distance: 5_000, previewPolyline: Trip.encodePolyline(reversed ? Array(points.reversed()) : points))
    }
    private func prepare(_ trips: [Trip], pins: [UUID] = [], journeys: [Journey] = [], query: String = "") -> PreparedProfileHistory {
        PreparedProfileHistory(library: ProfileHistoryLibrary(trips: trips), journeys: journeys,
                               query: query, from: nil, to: nil, language: .ru, calendar: calendar, pinnedTripIds: pins)
    }

    func testDirectionsAndThreshold() {
        let trips = [trip(3), trip(2, reversed: true), trip(1)]
        XCTAssertTrue(HistoryFolding.routineTripIds(trips: Array(trips.prefix(2)), calendar: calendar).isEmpty)
        XCTAssertEqual(HistoryFolding.routineTripIds(trips: trips, calendar: calendar), Set(trips.map(\.id)))
    }

    func testExclusionTable() {
        let modifiers: [(String, (inout Trip) -> Void)] = [
            ("photo", { $0.photos = [TripPhoto(id: UUID(), filename: "photo.jpg", caption: nil, timestamp: self.date(3))] }),
            ("checkpoint", { $0.checkpoints = [TripCheckpoint(timestamp: self.date(3), latitude: 45, longitude: 39,
                                                             distanceFromStart: 0, elapsedFromStart: 0)] }),
            ("description", { $0.tripDescription = "A memorable drive" }),
            ("draft", { $0.confirmation = .draft }),
            ("unfinished", { $0.endDate = nil }),
            ("no preview", { $0.previewPolyline = nil }),
            ("invalid preview", { $0.previewPolyline = Data([1, 2]) })
        ]
        for (name, modify) in modifiers {
            var candidate = trip(3)
            modify(&candidate)
            XCTAssertTrue(HistoryFolding.routineTripIds(trips: [candidate, trip(2), trip(1)], calendar: calendar).isEmpty, name)
        }
        var emptyNote = trip(3)
        emptyNote.tripDescription = " \n "
        XCTAssertEqual(HistoryFolding.routineTripIds(trips: [emptyNote, trip(2), trip(1)], calendar: calendar).count, 3)
    }

    func testPinnedAndJourneyNeverFold() {
        let trips = [trip(4), trip(3), trip(2), trip(1)]
        let ids = HistoryFolding.routineTripIds(trips: trips, pinnedTripIds: [trips[0].id], calendar: calendar)
        XCTAssertEqual(ids, Set(trips.dropFirst().map(\.id)))
        let journey = Journey(startDate: date(3), endDate: date(5))
        XCTAssertTrue(HistoryFolding.routineTripIds(trips: trips, journeys: [journey], calendar: calendar).isEmpty)
    }

    func testPrecisionSixUsesCellsNotExactCoordinatesOrCoarserCells() {
        var inside = trip(3)
        var points = Trip.decodePolyline(inside.previewPolyline!)
        points[0].latitude += 0.0001
        inside.previewPolyline = Trip.encodePolyline(points)
        XCTAssertEqual(HistoryFolding.routineTripIds(trips: [inside, trip(2), trip(1)], calendar: calendar).count, 3)
        var outside = trip(3)
        points[0] = GeohashEncoder.centerCoordinate(of: "ucftjm")
        outside.previewPolyline = Trip.encodePolyline(points)
        XCTAssertTrue(HistoryFolding.routineTripIds(trips: [outside, trip(2), trip(1)], calendar: calendar).isEmpty)
    }

    func testMonthsDoNotContributeToEachOthersThreshold() {
        XCTAssertTrue(HistoryFolding.routineTripIds(trips: [trip(2), trip(1), trip(30, month: 9)], calendar: calendar).isEmpty)
        let october = [trip(3), trip(2), trip(1)]
        let september = [trip(30, month: 9), trip(29, month: 9), trip(28, month: 9)]
        let prepared = prepare(october + september)
        XCTAssertEqual(prepared.chapters.count, 2)
        XCTAssertEqual(prepared.rows.count, 2)
        XCTAssertEqual(prepared.gridRuns.flatMap { $0 }.count, 6, "Grid keeps individual routine trips")
    }

    func testOneRoutineRowAtLatestRoutinePositionWithDistinctTitleSamples() {
        var routine = (1...8).reversed().map { trip($0) }
        for index in routine.indices { routine[index].title = index.isMultiple(of: 2) ? "Work" : "Town" }
        var notable = trip(9)
        notable.tripDescription = "Mountains"
        let result = prepare([notable] + routine)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows.first?.id, notable.id)
        guard case .routine(let group) = result.rows[1] else { return XCTFail("Expected routine row") }
        XCTAssertEqual(group.trips.map(\.id), routine.map(\.id))
        XCTAssertEqual(group.distance, 40_000)
        XCTAssertEqual(group.titleTrips.compactMap(\.title), ["Work", "Town"])
    }

    func testPinsFirstInSavedOrderWithoutChapterOrJourneyDoubles() {
        let trips = [trip(4), trip(3), trip(2), trip(1)]
        let pins = [trips[3].id, trips[0].id]
        let result = prepare(trips, pins: pins, journeys: [Journey(startDate: date(1), endDate: date(5))])
        XCTAssertEqual(result.pinned.map(\.id), pins)
        let chapterIds = result.chapters.flatMap(\.rows).flatMap { row -> [UUID] in
            switch row {
            case .trip(let trip): return [trip.id]
            case .journey(_, let legs): return legs.map(\.id)
            case .routine(let group): return group.trips.map(\.id)
            }
        }
        XCTAssertTrue(Set(chapterIds).isDisjoint(with: pins))
        XCTAssertEqual(Set(chapterIds + result.pinned.map(\.id)), Set(trips.map(\.id)))
    }

    func testSummaryCountsOriginalTripsAndDistinctRegionsIncludingPins() {
        var trips = [trip(4), trip(3), trip(2), trip(1)]
        for index in trips.indices { trips[index].region = index < 2 ? "Berlin" : "Brandenburg" }
        let result = prepare(trips, pins: [trips[0].id])
        let month = result.chapters[0]
        XCTAssertEqual(month.distance, 20_000)
        XCTAssertEqual(month.tripCount, 4)
        XCTAssertEqual(month.regionCount, 2)
        XCTAssertEqual(month.title(language: .ru, now: date(22), calendar: calendar), "Октябрь")
        XCTAssertEqual(month.title(language: .ru, now: date(22, year: 2027), calendar: calendar), "Октябрь 2026")
        let metric = AppStrings.profileChapterSummary(.ru, distance: Measure.distance(metres: month.distance, unit: .km, lang: .ru), trips: 4, regions: 2)
        XCTAssertEqual(metric, "20 км · 4 поездки · 2 региона")
    }

    func testJourneyChapterUsesStartMonthAndSearchExposesTrips() {
        let trips = [trip(2), trip(1), trip(30, month: 9)]
        let journey = Journey(startDate: date(29, month: 9), endDate: date(3))
        let result = prepare(trips, journeys: [journey])
        XCTAssertEqual(result.chapters.map(\.id), [calendar.dateInterval(of: .month, for: date(29, month: 9))!.start])
        var named = trips
        for index in named.indices { named[index].title = "Work" }
        XCTAssertEqual(prepare(named, journeys: [journey], query: "Work").rows.count, 3)
    }

    func testDifferentRoutineRoutesShareOneMonthlyRowButKeepTheirOwnThreshold() {
        let first = [trip(9), trip(8), trip(7)]
        var second = [trip(6), trip(5), trip(4)]
        let preview = Trip.encodePolyline([GeohashEncoder.centerCoordinate(of: "ucftjm"),
                                           GeohashEncoder.centerCoordinate(of: "ucftm2")])
        for index in second.indices { second[index].previewPolyline = preview }
        XCTAssertTrue(HistoryFolding.routineTripIds(trips: Array(first.prefix(2)) + Array(second.prefix(2)), calendar: calendar).isEmpty)
        let prepared = prepare(first + second)
        XCTAssertEqual(prepared.rows.count, 1)
        guard case .routine(let group) = prepared.rows[0] else { return XCTFail("Expected one monthly fold") }
        XCTAssertEqual(group.trips.count, 6)
        XCTAssertEqual(group.id, first[0].id)
    }

    func testPublicGridKeepsJourneyLegsAndOmitsPinsThroughTheFoldingBoundary() {
        let trips = [trip(4), trip(3), trip(2), trip(1)]
        let journey = Journey(startDate: date(1), endDate: date(5))
        let result = PreparedProfileHistory(
            library: ProfileHistoryLibrary(trips: trips), journeys: [journey], query: "", from: nil, to: nil,
            language: .en, calendar: calendar, pinnedTripIds: [trips[0].id], foldsRoutine: false,
            keepsEmptyJourneys: false, foldsJourneysInGrid: false)
        XCTAssertEqual(result.rows.map(\.id), [journey.id])
        XCTAssertEqual(result.pinned.map(\.id), [trips[0].id])
        XCTAssertEqual(result.gridRuns.flatMap { $0 }.map(\.id), Array(trips.dropFirst()).map(\.id))
    }

    func testForeignUnknownFieldsNeverFold() {
        let trips = [trip(3), trip(2), trip(1)]
        let result = PreparedProfileHistory(library: ProfileHistoryLibrary(trips: trips), journeys: [], query: "", from: nil, to: nil,
                                            language: .en, calendar: calendar, foldsRoutine: false)
        XCTAssertEqual(result.rows.count, 3)
    }
}
