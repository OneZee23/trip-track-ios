import Foundation

/// Library-wide work belongs to a data load, not to a row render or a search.
/// A fresh value is built for every successful load, including edits that keep
/// the trip count and dates unchanged. The owner creates this off the main actor.
struct ProfileHistoryLibrary {
    let trips: [Trip]
    let historicalLevels: [UUID: Int]?

    init(trips: [Trip]) {
        self.trips = trips
        self.historicalLevels = TripLevelHistory.levels(for: trips)
    }
}

/// The history's render inputs, prepared together when their dependencies
/// change. Reading this value from SwiftUI body never filters, sorts or groups
/// the library. Grid/list mode only chooses which already prepared rows to draw.
struct PreparedProfileHistory {
    let visibleTrips: [Trip]
    let rows: [HistoryRow]
    let gridRuns: [[HistoryRow]]
    let historicalLevels: [UUID: Int]?
    let pinned: [Trip]
    let chapters: [ProfileHistoryMonth]

    init(
        library: ProfileHistoryLibrary, journeys: [Journey], query: String,
        from: Date?, to: Date?, language: LanguageManager.Language,
        calendar: Calendar = .current, pinnedTripIds: [UUID] = [],
        foldsRoutine: Bool = true, keepsEmptyJourneys: Bool = true, foldsJourneysInGrid: Bool = true
    ) {
        let visibleTrips = TripHistoryFilter.apply(
            library.trips, query: query, from: from, to: to,
            language: language, calendar: calendar
        )
        let journal = HistoryFolding.journal(
            trips: visibleTrips, journeys: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? journeys : [],
            pinnedTripIds: pinnedTripIds,
            range: HistoryFolding.dayRange(from: from, to: to, calendar: calendar), calendar: calendar,
            foldsRoutine: foldsRoutine && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            keepsEmptyJourneys: keepsEmptyJourneys)
        self.pinned = journal.pinned
        self.chapters = ProfileHistoryMonth.build(rows: journal.rows, trips: visibleTrips, calendar: calendar, language: language)
        self.visibleTrips = visibleTrips
        self.rows = journal.rows
        let grid = HistoryFolding.journal(
            trips: visibleTrips, journeys: foldsJourneysInGrid && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? journeys : [],
            pinnedTripIds: pinnedTripIds, range: HistoryFolding.dayRange(from: from, to: to, calendar: calendar),
            calendar: calendar, foldsRoutine: false, keepsEmptyJourneys: keepsEmptyJourneys)
        self.gridRuns = HistoryFolding.runs(grid.rows)
        // Filters hide trips; they do not remove the XP earned before them.
        self.historicalLevels = library.historicalLevels
    }

    static let empty = PreparedProfileHistory(
        library: ProfileHistoryLibrary(trips: []), journeys: [], query: "",
        from: nil, to: nil, language: .en
    )
}
