import Foundation

/// Группы списка черновиков: «Сегодня», «Вчера», «Раньше» (спека §3).
///
/// Чистой функцией, потому что вопрос «в какую группу попала запись» решается
/// календарём, а календарь у человека свой: границу дня нельзя считать
/// вычитанием суток из «сейчас» — в день перевода часов сутки не двадцать
/// четыре часа.
enum DraftsGrouping {

    enum Bucket: String, CaseIterable {
        case today, yesterday, earlier
    }

    struct Group: Identifiable {
        let bucket: Bucket
        let trips: [Trip]
        var id: String { bucket.rawValue }
    }

    /// Разложить по группам, сохранив порядок внутри: свежие сверху.
    ///
    /// Пустые группы не рисуются — заголовок над пустотой ничего не называет.
    static func build(_ trips: [Trip], now: Date = Date(),
                      calendar: Calendar = .current) -> [Group] {
        let sorted = trips.sorted { $0.startDate > $1.startDate }
        var buckets: [Bucket: [Trip]] = [:]
        for trip in sorted {
            buckets[bucket(for: trip.startDate, now: now, calendar: calendar), default: []].append(trip)
        }
        return Bucket.allCases.compactMap { bucket in
            guard let trips = buckets[bucket], !trips.isEmpty else { return nil }
            return Group(bucket: bucket, trips: trips)
        }
    }

    static func bucket(for date: Date, now: Date = Date(),
                       calendar: Calendar = .current) -> Bucket {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }
}
