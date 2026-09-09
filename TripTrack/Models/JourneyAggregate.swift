import Foundation
import CoreLocation

/// Что путешествие показывает: плечи по дням, местные поездки свёрнуты,
/// итог. Чистая функция от поездок — ничего не хранится дважды.
struct JourneyAggregate: Equatable {
    enum Item: Equatable {
        /// Плечо дороги: одна поездка.
        case leg(Trip)
        /// Местные поездки у ночёвки: оба конца в `localRadius` от якоря.
        /// Второй параметр — якорь (координата ночёвки) для имени «Тбилиси».
        ///
        /// `lastDayNumber` — номер дня ПОСЛЕДНЕЙ поездки стоянки: она тянется
        /// через несколько дней («ДНИ 2–4»), и правый конец этого диапазона
        /// известен только здесь, где стоянка и собиралась. Экран считал его
        /// сам, своей копией той же арифметики дней, — две копии одного
        /// правила, которые расходятся молча.
        case local([Trip], anchor: CLLocationCoordinate2D, lastDayNumber: Int)
    }
    struct Day: Equatable {
        let number: Int
        let date: Date
        var items: [Item]
    }

    /// Оба конца поездки ближе этого к ночёвке — поездка «по городу».
    static let localRadius: CLLocationDistance = 30_000

    let days: [Day]
    let legCount: Int
    let totalMetres: Double
    let drivingSeconds: TimeInterval
    let calendarDays: Int
    let regions: [String]
    let firstStart: CLLocationCoordinate2D?
    /// Самый дальний от старта финиш — вторая половина имени «Краснодар —
    /// Тбилиси».
    ///
    /// Считается ТОЛЬКО по плечам: местные поездки в счёт не идут. Оба их конца
    /// лежат в `localRadius` от ночёвки, то есть дальше плеча, которое туда
    /// привезло, они не уедут никогда, — а вот перебить его на пару километров
    /// вполне могут. Тогда «дальней точкой» стала бы поездка в тбилисский
    /// супермаркет, и геокодер подписал бы путешествие его районом вместо
    /// города.
    let farthestEnd: CLLocationCoordinate2D?

    static func build(trips input: [Trip], calendar: Calendar = .current) -> JourneyAggregate {
        let trips = input.sorted { $0.startDate < $1.startDate }
        guard let first = trips.first else {
            return JourneyAggregate(days: [], legCount: 0, totalMetres: 0, drivingSeconds: 0,
                                    calendarDays: 0, regions: [], firstStart: nil, farthestEnd: nil)
        }
        let day0 = calendar.startOfDay(for: first.startDate)
        var days: [Day] = []
        var anchor: CLLocationCoordinate2D? = endCoordinate(of: first)
        var legCount = 0
        var farthest: (CLLocationCoordinate2D, CLLocationDistance)?
        let origin = startCoordinate(of: first)

        for trip in trips {
            let number = calendar.dateComponents([.day], from: day0, to: calendar.startOfDay(for: trip.startDate)).day! + 1
            let isLocal: Bool = {
                guard let anchor, let s = startCoordinate(of: trip), let e = endCoordinate(of: trip) else { return false }
                return distance(s, anchor) <= localRadius && distance(e, anchor) <= localRadius
            }()
            if isLocal, let anchor {
                // Свёрнутая стоянка живёт в дне, где началась, и копит все местные
                // поездки до следующего плеча — «Дни 2–4 · Тбилиси».
                if let i = days.indices.last, case .local(var list, let a, _) = days[i].items.last {
                    list.append(trip)
                    days[i].items[days[i].items.count - 1] = .local(list, anchor: a, lastDayNumber: number)
                } else {
                    appendItem(.local([trip], anchor: anchor, lastDayNumber: number),
                               number: number, date: trip.startDate, to: &days)
                }
            } else {
                legCount += 1
                appendItem(.leg(trip), number: number, date: trip.startDate, to: &days)
                anchor = endCoordinate(of: trip) ?? anchor
                if let origin, let e = endCoordinate(of: trip) {
                    let d = distance(origin, e)
                    if d > (farthest?.1 ?? -1) { farthest = (e, d) }
                }
            }
        }
        // Дни считаются от первого СТАРТА до последнего ФИНИША: плечо,
        // доехавшее за полночь, честно занимает следующий день — человек всё
        // ещё за рулём. `Day.number` внутри цикла мерит от старта каждой
        // поездки (это про то, к какому дню отнести карточку), а тут — про то,
        // сколько календарных дней заняло путешествие целиком; это разные
        // вопросы, и последнему нужен именно endDate.
        let last = trips.last!
        let span = calendar.dateComponents([.day], from: day0, to: calendar.startOfDay(for: last.endDate ?? last.startDate)).day! + 1
        var regions: [String] = []
        for r in trips.compactMap(\.region) where !regions.contains(r) { regions.append(r) }
        return JourneyAggregate(
            days: days, legCount: legCount,
            totalMetres: trips.reduce(0) { $0 + $1.distance },
            drivingSeconds: trips.reduce(0) { $0 + $1.duration },
            calendarDays: span, regions: regions,
            firstStart: origin, farthestEnd: farthest?.0)
    }

    /// Сколько поездок свёрнуто по стоянкам — «6 поездок · 2 по городу» на
    /// карточке. Не `legCount`: тот про дорогу, этот про то, что дорогой не был.
    var localTripCount: Int {
        days.reduce(0) { total, day in
            total + day.items.reduce(0) { acc, item in
                if case .local(let trips, _, _) = item { return acc + trips.count }
                return acc
            }
        }
    }

    /// «Краснодар — Тбилиси»; без имён — nil, экран покажет даты.
    func defaultTitle(startName: String?, farthestName: String?) -> String? {
        guard let s = startName, let f = farthestName, !s.isEmpty, !f.isEmpty, s != f else { return startName ?? farthestName }
        return "\(s) — \(f)"
    }

    private static func appendItem(_ item: Item, number: Int, date: Date, to days: inout [Day]) {
        if let i = days.indices.last, days[i].number == number {
            days[i].items.append(item)
        } else {
            days.append(Day(number: number, date: date, items: [item]))
        }
    }

    /// Точки трека, если поездка их несёт, иначе — упрощённая полилиния ЧЕРЕЗ
    /// КЭШ (`Trip.previewCoordinates`): `decodePolyline` напрямую разбирал одни
    /// и те же байты заново на каждый вход в экран и на каждую карточку в
    /// списке, хотя ответ уже лежал в `NSCache` рядом.
    static func startCoordinate(of trip: Trip) -> CLLocationCoordinate2D? {
        if let p = trip.trackPoints.first { return p.coordinate }
        return trip.previewCoordinates.first
    }
    static func endCoordinate(of trip: Trip) -> CLLocationCoordinate2D? {
        if let p = trip.trackPoints.last { return p.coordinate }
        return trip.previewCoordinates.last
    }
    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
