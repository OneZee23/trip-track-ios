import Foundation
import CoreLocation

/// «Похоже на путешествие»: правило, которое предлагает объединить поездки.
///
/// Всё, что здесь есть, стоит на одной мысли: **путешествие — это ночь не
/// дома**. Не километры (коммьют на 80 км каждый день дальше, чем поездка на
/// дачу) и не длительность (можно простоять полдня в пробке во дворе). Ночь
/// отделяет «уехал» от «съездил» без единого исключения, и потому правило
/// умещается в чистую функцию, которую проверяет тест, а не поездка.
///
/// Функция ничего не создаёт: она возвращает цепочку, а решает человек в листе
/// создания. Поэтому лучше промолчать, чем предложить неверное — пропущенную
/// цепочку он соберёт руками — долгим нажатием на карточку, — а на ложную
/// подсказку ответит «нет» и
/// перестанет читать эту карточку вовсе.
enum JourneySuggester {
    /// Дальше этого от дома — «не дома» (ночь считается ночью в путешествии).
    static let awayRadius: CLLocationDistance = 50_000
    /// Ближе этого к дому — «дома»: цепочка отсюда начинается и сюда
    /// закрывается.
    static let homeRadius: CLLocationDistance = 5_000
    /// Разрыв в записи больше недели рвёт цепочку: это уже другая история.
    static let silence: TimeInterval = 7 * 86_400

    /// Ячейка geohash-7 — примерно 150×150 м: один двор, а не квартал.
    static let cellPrecision = 7
    /// Ниже этого вывод дома — гадание, а один неверный дом отравляет все
    /// подсказки разом.
    static let minHomeNights = 10
    static let minHomeSpanDays = 14
    /// Обычная среда: работа, дача, родители — места, куда возвращаются.
    static let usualVisits = 3
    static let usualWindow: TimeInterval = 30 * 86_400
    /// Через столько после «Нет» вопрос про дом задаётся снова.
    ///
    /// Месяц, а не «никогда» и не «завтра»: «нет» чаще всего означает, что
    /// данных было мало и вывод показал работу вместо двора, — а не что
    /// человек отказался от дома навсегда. За месяц ночей накопится вдвое
    /// больше, и вывод будет уже другим. Переспросить назавтра тем же ответом
    /// значило бы не услышать его.
    static let homeReaskDelay: TimeInterval = 30 * 86_400

    /// Задавать ли вопрос «Это твой дом?».
    ///
    /// Чистая функция от четырёх фактов, а не три `if` внутри экрана: правило
    /// «нет — это на месяц, да — это навсегда» проверяется тестом.
    static func shouldAskHome(homeLocation: CLLocationCoordinate2D?,
                              homeAsked: Bool,
                              declinedAt: Date?,
                              now: Date) -> Bool {
        // Дом уже известен — спрашивать не о чем.
        guard homeLocation == nil else { return false }
        // «Да» закрывает вопрос навсегда: дом либо стоит в настройках, либо
        // его оттуда стёрли руками, и переспрашивать про стёртое — навязчиво.
        guard !homeAsked else { return false }
        guard let declinedAt else { return true }
        return now.timeIntervalSince(declinedAt) >= homeReaskDelay
    }

    /// Подсказка уместна по горячим следам. Без этого окна каждое открытие
    /// «Моих» предлагало бы объединить поездку двухлетней давности — человек
    /// один раз ответил «не сейчас» другой цепочке, и следом получил бы
    /// очередь из всех остальных.
    static let recency: TimeInterval = 14 * 86_400

    // MARK: - Дом

    /// Дом — ячейка geohash-7, где чаще всего кончается поездка ночью
    /// (18:00–06:00 местного), при ≥10 ночах за ≥14 дней данных.
    ///
    /// Считаются НОЧИ, а не концы поездок: три выезда за вечер из одного двора
    /// — это одна ночь дома, иначе «дом» уехал бы туда, откуда чаще ездят.
    /// Возвращается среднее по концам победившей ячейки, а не её центр: центр
    /// может лежать за углом, а среднее — там, где машина реально стоит.
    static func inferHome(trips: [Trip], calendar: Calendar = .current) -> CLLocationCoordinate2D? {
        var nightsByCell: [String: Set<Date>] = [:]
        var pointsByCell: [String: [CLLocationCoordinate2D]] = [:]
        var earliest: Date?
        var latest: Date?

        for trip in trips {
            let finish = trip.endDate ?? trip.startDate
            earliest = min(earliest ?? trip.startDate, trip.startDate)
            latest = max(latest ?? finish, finish)
            guard let end = JourneyAggregate.endCoordinate(of: trip) else { continue }
            let hour = calendar.component(.hour, from: finish)
            guard hour >= 18 || hour < 6 else { continue }
            // Ночь принадлежит вечеру, а не календарной дате: конец в 01:00 —
            // та же ночь, что и конец в 23:00 накануне.
            let night = calendar.startOfDay(for: finish.addingTimeInterval(-6 * 3_600))
            let cell = GeohashEncoder.encode(latitude: end.latitude, longitude: end.longitude,
                                             precision: cellPrecision)
            nightsByCell[cell, default: []].insert(night)
            pointsByCell[cell, default: []].append(end)
        }

        guard let earliest, let latest else { return nil }
        let span = (calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest),
                                            to: calendar.startOfDay(for: latest)).day ?? 0) + 1
        guard span >= minHomeSpanDays else { return nil }
        // При равенстве побеждает ячейка с бо́льшим числом концов, потом —
        // меньшая по коду: иначе ответ зависел бы от порядка словаря и
        // «дом» прыгал бы между двумя дворами от запуска к запуску.
        guard let winner = nightsByCell.keys.max(by: { a, b in
            let (na, nb) = (nightsByCell[a]?.count ?? 0, nightsByCell[b]?.count ?? 0)
            if na != nb { return na < nb }
            let (pa, pb) = (pointsByCell[a]?.count ?? 0, pointsByCell[b]?.count ?? 0)
            if pa != pb { return pa < pb }
            return a > b
        }), (nightsByCell[winner]?.count ?? 0) >= minHomeNights else { return nil }

        let points = pointsByCell[winner] ?? []
        guard !points.isEmpty else { return nil }
        return CLLocationCoordinate2D(
            latitude: points.reduce(0) { $0 + $1.latitude } / Double(points.count),
            longitude: points.reduce(0) { $0 + $1.longitude } / Double(points.count))
    }

    // MARK: - Подсказка

    /// Цепочка поездок с ночью не дома, закрытая возвращением домой:
    /// кандидат в путешествие. Возвращает поездки цепочки (≥2) или nil.
    ///
    /// Порядок разбора — с конца: последняя цепочка интереснее давней, и
    /// каждая следующая назад проверяется, только если ближняя не подошла.
    static func suggestion(trips: [Trip], home: CLLocationCoordinate2D,
                           existing: [Journey], now: Date,
                           calendar: Calendar = .current) -> [Trip]? {
        let ordered = trips.sorted { $0.startDate < $1.startDate }
        // Поездка, уже лежащая в путешествии, — стена, а не пустое место:
        // сцепить через её голову соседей значило бы предложить объединить
        // то, что человек уже разложил руками.
        let taken = Set(ordered.filter { trip in existing.contains { $0.contains(trip) } }.map(\.id))

        var index = ordered.count - 1
        while index >= 0 {
            let last = ordered[index]
            let finish = last.endDate ?? last.startDate
            guard now.timeIntervalSince(finish) <= recency else { return nil }
            if !taken.contains(last.id), let end = JourneyAggregate.endCoordinate(of: last),
               let chain = chain(endingAt: index, in: ordered, home: home, taken: taken) {
                // Обычная среда считается по поездкам ВНЕ самой цепочки —
                // потому и считается здесь, когда цепочка уже собрана, а не
                // один раз до цикла. Четыре вечера, возвращённые в один и тот
                // же отель, — это три «визита» в его ячейку, и по общему счёту
                // отель становился «обычной средой» сам себе: ночи поездки
                // отменяли поездку. Из чужих поездок ячейка отеля не наберёт
                // ничего, а работа и дача наберут — они на то и обычные, что
                // человек ездит туда и вне этой недели.
                let usual = usualCells(ordered, excluding: Set(chain.map(\.id)), now: now)
                if isSettled(end, home: home, usual: usual),
                   hasNightAway(chain, home: home, usual: usual, calendar: calendar) {
                    return chain
                }
            }
            index -= 1
        }
        return nil
    }

    // MARK: - Цепочка вокруг опорной

    /// Разрыв, который цепочку ещё не рвёт: полторы суток.
    ///
    /// Не `silence` (неделя): та отвечает на вопрос подсказки — «одна ли это
    /// история», и неделя молчания внутри поездки в Грузию бывает. Здесь
    /// вопрос другой и куда более узкий: какие поездки предотметить человеку,
    /// который открыл лист сборки. Тридцать шесть часов — это «уехал вчера и
    /// доехал сегодня», с запасом на ночь и на полдня стоянки; неделя же
    /// предотметила бы ему весь месяц, и он снова не понял бы, что происходит.
    static let chainGap: TimeInterval = 36 * 3_600

    /// Поездки, сцепленные с опорной: конец одной там же, где начало
    /// следующей, и между ними не больше `chainGap`.
    ///
    /// Это НЕ `suggestion`: там правило решает, стоит ли заговорить первым, и
    /// потому спрашивает про дом и про ночь не дома. Здесь человек уже пришёл
    /// сам и показал пальцем на поездку — остаётся угадать, что ещё было той
    /// же дорогой. Дом в этом вопросе не участвует: «Краснодар → Геленджик» и
    /// «Геленджик → Дивноморское» — одна дорога независимо от того, где живёт
    /// человек и знает ли приложение его двор вообще.
    ///
    /// Возвращает цепочку по времени, вместе с опорной; поездка без координат
    /// в цепочку не входит и обрывает её — про неё нечего утверждать, а
    /// предотметить лишнее хуже, чем недоотметить: снятую галочку человек не
    /// заметит, а лишнее плечо уедет в путешествие молча.
    static func chainAround(_ anchor: Trip, in trips: [Trip]) -> [Trip] {
        let ordered = trips.sorted { $0.startDate < $1.startDate }
        guard let index = ordered.firstIndex(where: { $0.id == anchor.id }) else { return [anchor] }

        var chain = [ordered[index]]
        var back = index
        while back > 0, joins(ordered[back - 1], ordered[back]) {
            chain.insert(ordered[back - 1], at: 0)
            back -= 1
        }
        var forward = index
        while forward < ordered.count - 1, joins(ordered[forward], ordered[forward + 1]) {
            chain.append(ordered[forward + 1])
            forward += 1
        }
        return chain
    }

    /// Сцепляются ли две соседние по времени поездки.
    private static func joins(_ earlier: Trip, _ later: Trip) -> Bool {
        guard let end = JourneyAggregate.endCoordinate(of: earlier),
              let start = JourneyAggregate.startCoordinate(of: later) else { return false }
        let gap = later.startDate.timeIntervalSince(earlier.endDate ?? earlier.startDate)
        guard gap <= chainGap else { return false }
        return distance(start, end) <= homeRadius
    }

    /// Цепочка назад от закрывающей поездки, если она вообще складывается.
    ///
    /// Только геометрия и время: про «обычную среду» здесь не спрашивают —
    /// её нельзя посчитать, пока не известно, из чего цепочка состоит.
    private static func chain(endingAt last: Int, in ordered: [Trip],
                              home: CLLocationCoordinate2D,
                              taken: Set<UUID>) -> [Trip]? {
        var chain = [ordered[last]]
        var i = last
        while true {
            let front = ordered[i]
            if let start = JourneyAggregate.startCoordinate(of: front),
               distance(start, home) <= homeRadius {
                // Цепочка открылась выездом из дома — дальше назад не идём.
                guard chain.count >= 2 else { return nil }
                return chain
            }
            guard i > 0 else { return nil }
            let prev = ordered[i - 1]
            guard !taken.contains(prev.id),
                  let prevEnd = JourneyAggregate.endCoordinate(of: prev),
                  let frontStart = JourneyAggregate.startCoordinate(of: front) else { return nil }
            let gap = front.startDate.timeIntervalSince(prev.endDate ?? prev.startDate)
            guard gap <= silence else { return nil }
            // Сцепка: либо следующая поездка стартует там же, где кончилась
            // предыдущая, либо обе далеко от дома. Второе — не поблажка:
            // машину в Тбилиси переставляют на другую улицу, и по пяти метрам
            // порога поездка по городу оторвалась бы от собственной дороги.
            let sameSpot = distance(frontStart, prevEnd) <= homeRadius
            let bothAway = distance(prevEnd, home) >= awayRadius && distance(frontStart, home) >= awayRadius
            guard sameSpot || bothAway else { return nil }
            chain.insert(prev, at: 0)
            i -= 1
        }
    }

    /// Между какими-то соседними поездками цепочки прошло 02:00 местного, а
    /// машина стояла ДАЛЬШЕ `awayRadius` от дома и не в обычной среде.
    ///
    /// Порог тут именно `awayRadius` (50 км), а не «не дома» (5 км): ночь у
    /// друга через город — не путешествие, и по пятикилометровому порогу
    /// подсказка вылезала бы после каждой такой ночи. `homeRadius` отвечает на
    /// другой вопрос — где цепочка начинается и где закрывается.
    private static func hasNightAway(_ chain: [Trip], home: CLLocationCoordinate2D,
                                     usual: Set<String>, calendar: Calendar) -> Bool {
        for (a, b) in zip(chain, chain.dropFirst()) {
            guard let spot = JourneyAggregate.endCoordinate(of: a) else { continue }
            guard distance(spot, home) >= awayRadius,
                  !isSettled(spot, home: home, usual: usual) else { continue }
            let from = a.endDate ?? a.startDate
            // «02:00 местного» — по поясу ТЕЛЕФОНА, нарочно: человек ночует
            // там, где стоит его телефон, а поясов поездка пересекает сколько
            // угодно. Календарь берётся с часовым поясом устройства.
            guard let night = calendar.nextDate(after: from, matching: DateComponents(hour: 2, minute: 0),
                                                matchingPolicy: .nextTime) else { continue }
            if night <= b.startDate { return true }
        }
        return false
    }

    /// «Дома или всё равно что дома»: рядом с домом либо в обычной среде.
    private static func isSettled(_ point: CLLocationCoordinate2D,
                                  home: CLLocationCoordinate2D, usual: Set<String>) -> Bool {
        if distance(point, home) <= homeRadius { return true }
        return usual.contains(GeohashEncoder.encode(latitude: point.latitude,
                                                    longitude: point.longitude,
                                                    precision: cellPrecision))
    }

    /// Обычная среда: ячейки, где поездки кончались ≥3 раз за 30 дней —
    /// работа, дача, родители. Ночёвка там — не путешествие.
    ///
    /// `excluding` — поездки самой цепочки-кандидата. Своими ночами цепочка не
    /// голосует: иначе достаточно четырёх вечеров, возвращённых в один отель,
    /// чтобы отель стал «обычной средой» и путешествие отменило само себя.
    private static func usualCells(_ trips: [Trip], excluding chain: Set<UUID>,
                                   now: Date) -> Set<String> {
        var counts: [String: Int] = [:]
        for trip in trips where !chain.contains(trip.id) {
            let finish = trip.endDate ?? trip.startDate
            guard now.timeIntervalSince(finish) <= usualWindow, now >= finish,
                  let end = JourneyAggregate.endCoordinate(of: trip) else { continue }
            let cell = GeohashEncoder.encode(latitude: end.latitude, longitude: end.longitude,
                                             precision: cellPrecision)
            counts[cell, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= usualVisits }.keys)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
