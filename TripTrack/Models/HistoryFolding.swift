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
    ///
    /// Плеч не осталось вовсе — по началу окна: `.distantPast` уводил такую
    /// карточку в самый низ истории, на много лет от своих дат, где её уже не
    /// найти.
    var date: Date {
        switch self {
        case .trip(let t): return t.startDate
        case .journey(let j, let legs): return legs.first?.startDate ?? j.startDate
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
