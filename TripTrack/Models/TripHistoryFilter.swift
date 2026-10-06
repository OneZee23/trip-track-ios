import Foundation

/// Local-only history search. Date and text filters compose without changing
/// trip order or excluding a zero-distance trip from its calendar day.
enum TripHistoryFilter {
    static func apply(
        _ trips: [Trip], query: String, from: Date?, to: Date?,
        language: LanguageManager.Language, calendar: Calendar = .current
    ) -> [Trip] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard from != nil || !words.isEmpty else { return trips }
        let start = from.map { calendar.startOfDay(for: $0) }
        let end = (to ?? from).map { calendar.startOfDay(for: $0) }
        return trips.filter { trip in
            if let start, let end {
                let day = calendar.startOfDay(for: trip.startDate)
                guard day >= min(start, end), day <= max(start, end) else { return false }
            }
            guard !words.isEmpty else { return true }
            let searchable = [trip.title, trip.region,
                              RegionDisplay.localized(trip.region, language: language)]
                .compactMap { $0 }.joined(separator: " ")
            return words.allSatisfy {
                searchable.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive],
                                 locale: Locale(identifier: language.rawValue)) != nil
            }
        }
    }
}
