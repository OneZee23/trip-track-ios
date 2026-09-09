import Foundation
import CoreLocation

/// SDK не даёт `CLLocationCoordinate2D` сравнение из коробки, а без него
/// `JourneyAggregate` и `Item` не синтезируют `Equatable` (нужен тестам и
/// экрану путешествия для сравнения снапшотов).
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

/// Что путешествие показывает: плечи по дням, местные поездки свёрнуты,
/// итог. Чистая функция от поездок — ничего не хранится дважды.
struct JourneyAggregate: Equatable {
    enum Item: Equatable {
        /// Плечо дороги: одна поездка.
        case leg(Trip)
        /// Местные поездки у ночёвки: оба конца в `localRadius` от якоря.
        /// Второй параметр — якорь (координата ночёвки) для имени «Тбилиси».
        case local([Trip], anchor: CLLocationCoordinate2D)
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
                if let i = days.indices.last, case .local(var list, let a) = days[i].items.last {
                    list.append(trip); days[i].items[days[i].items.count - 1] = .local(list, anchor: a)
                } else {
                    appendItem(.local([trip], anchor: anchor), number: number, date: trip.startDate, to: &days)
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
        // Якорь на startDate, а не endDate: каждый Day.number выше уже считается
        // от начала поездки, и последняя поездка обязана мерить тем же. Ночной
        // бросок за 480 км с концом за полночь иначе уводил `calendarDays` от
        // таймзоны машины — по UTC счёт не переползал полночь, по Москве (+3)
        // переползал, и один и тот же тест давал 6 и 7 на разных машинах.
        let last = trips.last!
        let span = calendar.dateComponents([.day], from: day0, to: calendar.startOfDay(for: last.startDate)).day! + 1
        var regions: [String] = []
        for r in trips.compactMap(\.region) where !regions.contains(r) { regions.append(r) }
        return JourneyAggregate(
            days: days, legCount: legCount,
            totalMetres: trips.reduce(0) { $0 + $1.distance },
            drivingSeconds: trips.reduce(0) { $0 + $1.duration },
            calendarDays: span, regions: regions,
            firstStart: origin, farthestEnd: farthest?.0)
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

    static func startCoordinate(of trip: Trip) -> CLLocationCoordinate2D? {
        if let p = trip.trackPoints.first { return p.coordinate }
        return trip.previewPolyline.flatMap { Trip.decodePolyline($0).first }
    }
    static func endCoordinate(of trip: Trip) -> CLLocationCoordinate2D? {
        if let p = trip.trackPoints.last { return p.coordinate }
        return trip.previewPolyline.flatMap { Trip.decodePolyline($0).last }
    }
    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
