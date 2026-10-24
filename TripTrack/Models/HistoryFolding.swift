import Foundation

/// Строка «Истории» в профиле: своя поездка или путешествие со своими плечами.
///
/// Путешествие несёт плечи с собой, а не один id: карточка считает по ним итог
/// и рисует их миниатюры, и второй поход в базу за теми же поездками означал бы
/// две правды о том, что попало внутрь окна.
enum HistoryRow: Identifiable {
    case trip(Trip)
    case journey(Journey, legs: [Trip])
    case routine(ProfileRoutineTrips)

    var id: UUID {
        switch self {
        case .trip(let t): return t.id
        case .journey(let j, _): return j.id
        case .routine(let group): return group.id
        }
    }

    /// Дата, по которой строка встаёт в список. У путешествия это дата его
    /// ПОСЛЕДНЕГО плеча — карточка занимает место, где стояло бы самое новое
    /// из спрятанных плеч, и история не подпрыгивает от объединения.
    ///
    /// Плеч не осталось вовсе — по началу окна: `.distantPast` уводил такую
    /// карточку в самый низ истории, на много лет от своих дат, где её уже не
    /// найти.
    var date: Date {
        switch self {
        case .trip(let t): return t.startDate
        case .journey(let j, let legs): return legs.first?.startDate ?? j.startDate
        case .routine(let group): return group.trips[0].startDate
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
    /// `range` — отрезок календаря, которым уже отфильтрован `trips`. Нужен
    /// ровно для одного вопроса: пустое путешествие — это «плечи отрезал
    /// фильтр» или «плеч не осталось»? По одному списку поездок эти два случая
    /// неотличимы, а поступать с ними надо противоположно.
    static func fold(trips: [Trip], journeys: [Journey],
                     range: ClosedRange<Date>? = nil) -> [HistoryRow] {
        var rows: [HistoryRow] = []
        var taken: Set<UUID> = []
        for j in journeys {
            // `!taken.contains` — не украшение: локально окна пересечься не
            // могут (проверка стоит и на создании, и на правке), но приезжают
            // они с сервера, где эту проверку однажды может не пройти чужой
            // клиент. Поездка, попавшая в два окна, без этой строки нарисовалась
            // бы дважды — и километры в глазах человека удвоились бы.
            let legs = trips
                .filter { j.contains($0) && !taken.contains($0.id) }
                .sorted { $0.startDate > $1.startDate }
            // Окно, целиком лежащее вне отрезка календаря, — не строка:
            // человек смотрит сентябрь, и августовское путешествие в нём
            // висело бы пустой карточкой.
            //
            // А вот окно ВНУТРИ отрезка, у которого не осталось ни одного
            // плеча, строкой быть обязано. Плечи удаляются и убираются руками,
            // и раньше такое путешествие исчезало из истории насовсем — при
            // том, что даты оно продолжало занимать (`journeyOverlapping`), и
            // объединить те же дни заново уже не давало. Пустая карточка —
            // единственный способ до него дойти и удалить.
            guard !legs.isEmpty || intersects(j, range) else { continue }
            taken.formUnion(legs.map(\.id))
            rows.append(.journey(j, legs: legs))
        }
        rows += trips.filter { !taken.contains($0.id) }.map(HistoryRow.trip)
        return rows.sorted { $0.date > $1.date }
    }

    /// Canonical journal folding: pins first, journeys next, then one routine
    /// row per month. The original library remains intact for calendar/grid.
    static func journal(
        trips: [Trip], journeys: [Journey], pinnedTripIds: [UUID],
        range: ClosedRange<Date>? = nil, calendar: Calendar = .current,
        foldsRoutine: Bool = true, keepsEmptyJourneys: Bool = true
    ) -> (pinned: [Trip], rows: [HistoryRow]) {
        let byId = Dictionary(trips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var pinned: [Trip] = []
        var taken: Set<UUID> = []
        for id in pinnedTripIds.prefix(3) where !taken.contains(id) {
            guard let trip = byId[id] else { continue }
            pinned.append(trip)
            taken.insert(id)
        }
        let candidates = trips.filter { !taken.contains($0.id) }
        let folded = fold(trips: candidates, journeys: journeys, range: range).filter {
            if case .journey(_, let legs) = $0 { return keepsEmptyJourneys || !legs.isEmpty }
            return true
        }
        let routine = foldsRoutine
            ? routineTripIds(trips: trips, journeys: journeys, pinnedTripIds: Set(pinnedTripIds), calendar: calendar)
            : []
        let groups = Dictionary(grouping: candidates.filter { routine.contains($0.id) }) {
            calendar.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate
        }.mapValues { $0.sorted { $0.startDate > $1.startDate } }
        var inserted: Set<Date> = []
        var rows: [HistoryRow] = []
        for row in folded {
            if case .trip(let trip) = row, routine.contains(trip.id) {
                let month = calendar.dateInterval(of: .month, for: trip.startDate)?.start ?? trip.startDate
                if inserted.insert(month).inserted, let group = groups[month] { rows.append(.routine(ProfileRoutineTrips(trips: group))) }
            } else {
                rows.append(row)
            }
        }
        return (pinned, rows)
    }

    /// Pure rule, using only the preview (never the full track or a cache
    /// keyed by id). Missing preview and incomplete records cannot qualify.
    static func routineTripIds(
        trips: [Trip], journeys: [Journey] = [], pinnedTripIds: Set<UUID> = [],
        calendar: Calendar = .current
    ) -> Set<UUID> {
        struct Route: Hashable {
            let month: Date
            let a: String
            let b: String
        }
        var groups: [Route: [UUID]] = [:]
        for trip in trips {
            guard !trip.isDraft, trip.endDate != nil, trip.photos.isEmpty,
                  trip.checkpoints.isEmpty, (trip.tripDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !pinnedTripIds.contains(trip.id), !journeys.contains(where: { $0.contains(trip) }),
                  let preview = trip.previewPolyline else { continue }
            let points = Trip.decodePolyline(preview)
            guard points.count >= 2, let first = points.first, let last = points.last,
                  first.latitude.isFinite, first.longitude.isFinite,
                  last.latitude.isFinite, last.longitude.isFinite,
                  (-90...90).contains(first.latitude), (-180...180).contains(first.longitude),
                  (-90...90).contains(last.latitude), (-180...180).contains(last.longitude) else { continue }
            let start = GeohashEncoder.encode(latitude: first.latitude, longitude: first.longitude, precision: 6)
            let end = GeohashEncoder.encode(latitude: last.latitude, longitude: last.longitude, precision: 6)
            let month = calendar.dateInterval(of: .month, for: trip.startDate)?.start ?? trip.startDate
            groups[Route(month: month, a: min(start, end), b: max(start, end)), default: []].append(trip.id)
        }
        return Set(groups.values.filter { $0.count >= 3 }.flatMap { $0 })
    }

    /// Пересекается ли окно с отрезком календаря. Отрезка нет — видно всё,
    /// значит пересекается по определению. Открытое окно (`endDate == nil`)
    /// тянется вперёд до конца времён.
    private static func intersects(_ j: Journey, _ range: ClosedRange<Date>?) -> Bool {
        guard let range else { return true }
        // Верхняя граница — начало СЛЕДУЮЩИХ суток, поэтому сравнение строгое:
        // сама она в отрезок не входит (см. `dayRange`).
        return j.startDate < range.upperBound && (j.endDate ?? .distantFuture) >= range.lowerBound
    }

    /// Отрезок календаря в том же виде, в каком его понимает фильтр «Моих»:
    /// от начала первых суток до начала суток, СЛЕДУЮЩИХ за последними, — один
    /// тап по-прежнему один день.
    ///
    /// Верхний конец исключающий (`intersects` сравнивает строго), а не
    /// «полночь минус секунда»: та секунда — щель, в которую проваливалось
    /// окно, начавшееся в последние 999 миллисекунд суток. Секунда до полуночи
    /// вычиталась ради того, чтобы конец отрезка попадал в те же сутки, что и
    /// его дата, — но проверка тут одна, и ей достаточно знать, где сутки
    /// кончаются.
    static func dayRange(from: Date?, to: Date?, calendar: Calendar = .current) -> ClosedRange<Date>? {
        guard let from else { return nil }
        let start = calendar.startOfDay(for: from)
        // `addingTimeInterval(86_400)` — ровно 24 часа, но не ровно сутки: в
        // день перевода часов граница съезжала на час и роняла последний час
        // суток из окна. `calendar.date(byAdding:)` считает календарными
        // сутками, а не секундами.
        let dayAfter = calendar.startOfDay(for: to ?? from)
        let end = calendar.date(byAdding: .day, value: 1, to: dayAfter) ?? dayAfter.addingTimeInterval(86_400)
        return start...max(start, end)
    }

    /// Куски для сетки: подряд идущие поездки — одной решёткой, каждое
    /// путешествие — само по себе (его карточка идёт во всю ширину, а колонку
    /// `LazyVGrid` на две клетки не растянуть).
    static func runs(_ rows: [HistoryRow]) -> [[HistoryRow]] {
        var runs: [[HistoryRow]] = []
        for row in rows {
            switch row {
            case .journey, .routine:
                runs.append([row])
            case .trip:
                if let lastIndex = runs.indices.last, case .trip = runs[lastIndex][0] {
                    // Mutate through the array's subscript. Copying `last`
                    // out first shares its buffer with `runs`, so appending
                    // copies the growing run on every trip (quadratic work).
                    runs[lastIndex].append(row)
                } else {
                    runs.append([row])
                }
            }
        }
        return runs
    }
}
