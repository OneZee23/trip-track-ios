import Foundation

/// A chapter owns rows by the trip/journey start month. Summary counts the
/// original trips in that month, including pins and folded journey legs.
struct ProfileHistoryMonth: Identifiable {
    let id: Date
    let heading: String
    let rows: [HistoryRow]
    let distance: Double
    let tripCount: Int
    let regionCount: Int

    static func build(rows: [HistoryRow], trips: [Trip], calendar: Calendar, language: LanguageManager.Language = .en) -> [Self] {
        func month(_ date: Date) -> Date {
            calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
        let tripGroups = Dictionary(grouping: trips) { month($0.startDate) }
        let rowGroups = Dictionary(grouping: rows) { row in
            if case .journey(let journey, _) = row { return month(journey.startDate) }
            return month(row.date)
        }
        return rowGroups.keys.sorted(by: >).map { date in
            let originals = tripGroups[date] ?? []
            return Self(id: date, heading: title(date, language: language, now: Date(), calendar: calendar), rows: rowGroups[date] ?? [],
                        distance: originals.reduce(0) { $0 + $1.distance }, tripCount: originals.count,
                        regionCount: Set(originals.compactMap(\.region).filter { !$0.isEmpty }).count)
        }
    }

    func title(language: LanguageManager.Language, now: Date = Date(), calendar: Calendar = .current) -> String {
        Self.title(id, language: language, now: now, calendar: calendar)
    }

    private static func title(_ date: Date, language: LanguageManager.Language, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? "LLLL" : "LLLL yyyy"
        return formatter.string(from: date).capitalized(with: language.locale)
    }
}
