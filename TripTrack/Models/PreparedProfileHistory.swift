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

    init(
        library: ProfileHistoryLibrary, journeys: [Journey], query: String,
        from: Date?, to: Date?, language: LanguageManager.Language,
        calendar: Calendar = .current
    ) {
        let visibleTrips = TripHistoryFilter.apply(
            library.trips, query: query, from: from, to: to,
            language: language, calendar: calendar
        )
        let rows: [HistoryRow]
        // Search exposes matching legs directly; a collapsed journey would
        // conceal the title the person searched for.
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows = HistoryFolding.fold(
                trips: visibleTrips, journeys: journeys,
                range: HistoryFolding.dayRange(from: from, to: to, calendar: calendar)
            )
        } else {
            rows = visibleTrips.map(HistoryRow.trip)
        }
        self.visibleTrips = visibleTrips
        self.rows = rows
        self.gridRuns = HistoryFolding.runs(rows)
        // Filters hide trips; they do not remove the XP earned before them.
        self.historicalLevels = library.historicalLevels
    }

    static let empty = PreparedProfileHistory(
        library: ProfileHistoryLibrary(trips: []), journeys: [], query: "",
        from: nil, to: nil, language: .en
    )
}
