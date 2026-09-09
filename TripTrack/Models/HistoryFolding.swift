import Foundation

/// Строка «Истории» в профиле: своя поездка или путешествие со своими плечами.
///
/// Путешествие несёт плечи с собой, а не один id: карточка считает по ним итог
/// и рисует их миниатюры, и второй поход в базу за теми же поездками означал бы
/// две правды о том, что попало внутрь окна.
enum HistoryRow: Identifiable {
    case trip(Trip)
    case journey(Journey, legs: [Trip])

    var id: UUID {
        switch self {
        case .trip(let t): return t.id
        case .journey(let j, _): return j.id
        }
    }

    /// Дата, по которой строка встаёт в список. У путешествия это дата его
    /// ПОСЛЕДНЕГО плеча — карточка занимает место, где стояло бы самое новое
    /// из спрятанных плеч, и история не подпрыгивает от объединения.
    var date: Date {
        switch self {
        case .trip(let t): return t.startDate
        case .journey(_, let legs): return legs.first?.startDate ?? .distantPast
        }
    }
}

/// Плечи уходят внутрь карточки путешествия; всё остальное — как было.
///
/// Это ЕДИНСТВЕННОЕ место, где поездка прячется из списка. Ни статистика, ни
/// лента, ни календарь с километрами по дням про путешествия не знают: там
/// плечо — обычная поездка, и спрятать его значило бы стереть километры,
/// которые человек проехал.
enum HistoryFolding {
    static func fold(trips: [Trip], journeys: [Journey]) -> [HistoryRow] {
        var rows: [HistoryRow] = []
        var taken: Set<UUID> = []
        for j in journeys {
            let legs = trips.filter { j.contains($0) }.sorted { $0.startDate > $1.startDate }
            // Окно без единого плеча в видимом отрезке — не строка: календарь
            // отрезал сентябрь, а карточка августовского путешествия осталась
            // бы висеть пустой.
            guard !legs.isEmpty else { continue }
            taken.formUnion(legs.map(\.id))
            rows.append(.journey(j, legs: legs))
        }
        rows += trips.filter { !taken.contains($0.id) }.map(HistoryRow.trip)
        return rows.sorted { $0.date > $1.date }
    }

    /// Куски для сетки: подряд идущие поездки — одной решёткой, каждое
    /// путешествие — само по себе (его карточка идёт во всю ширину, а колонку
    /// `LazyVGrid` на две клетки не растянуть).
    static func runs(_ rows: [HistoryRow]) -> [[HistoryRow]] {
        var runs: [[HistoryRow]] = []
        for row in rows {
            switch row {
            case .journey:
                runs.append([row])
            case .trip:
                if var last = runs.last, case .trip = last[0] {
                    last.append(row)
                    runs[runs.count - 1] = last
                } else {
                    runs.append([row])
                }
            }
        }
        return runs
    }
}
