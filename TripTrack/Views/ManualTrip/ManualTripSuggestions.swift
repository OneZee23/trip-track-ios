import Foundation
import CoreLocation

/// Что лежит под полем «Откуда»/«Куда», пока человек ещё ничего не набрал
/// (редизайн 13 окт 2026, вариант A).
///
/// Вписывают чаще всего дорогу между уже знакомыми точками: от дома, до
/// дачи, обратно. Поэтому первый ответ даёт сама библиотека — без похода в
/// поиск Apple и без набора: «Дом», три частых места и концы недавних
/// поездок, ровно в этом порядке. Чистая функция, а не вычисление в `body`:
/// порядок и отсев дублей — правила, и держит их тест, а не открытый лист.
enum ManualTripSuggestions {
    struct Item: Identifiable, Equatable {
        enum Kind: Equatable { case home, place, recent }

        let kind: Kind
        let point: ManualTripPoint
        /// Вторая строка: где это или откуда это известно. `nil` — нечего
        /// сказать, и строки нет.
        let detail: String?

        var id: UUID { point.id }

        static func == (a: Item, b: Item) -> Bool {
            a.kind == b.kind && a.point.name == b.point.name
                && a.point.coordinate.latitude == b.point.coordinate.latitude
                && a.point.coordinate.longitude == b.point.coordinate.longitude
        }
    }

    /// Конец недавней поездки: где поездка началась или кончилась, и чем это
    /// место подписать.
    struct RecentEnd {
        let name: String
        let coordinate: CLLocationCoordinate2D
        let detail: String?
    }

    /// Две точки ближе этого — одно место: двор, из которого выезжали трижды,
    /// не должен занимать три строки. Тот же порядок, что ячейка места
    /// (`Place.cell`, ~150 м).
    static let sameSpotMetres: CLLocationDistance = 150
    /// Списку на одном экране с клавиатурой хватает пяти строк; дальше
    /// человек всё равно наберёт.
    static let limit = 5

    static func build(
        home: ManualTripPoint?,
        places: [ManualTripPoint],
        recent: [RecentEnd],
        excluding taken: CLLocationCoordinate2D? = nil,
        limit: Int = limit
    ) -> [Item] {
        var items: [Item] = []
        func isNew(_ coordinate: CLLocationCoordinate2D) -> Bool {
            if let taken, distance(taken, coordinate) < sameSpotMetres { return false }
            return !items.contains { distance($0.point.coordinate, coordinate) < sameSpotMetres }
        }
        if let home, isNew(home.coordinate) {
            items.append(Item(kind: .home, point: home, detail: nil))
        }
        for place in places where isNew(place.coordinate) {
            items.append(Item(kind: .place, point: place, detail: nil))
        }
        for end in recent where !end.name.isEmpty && isNew(end.coordinate) {
            items.append(Item(kind: .recent,
                              point: ManualTripPoint(name: end.name, coordinate: end.coordinate,
                                                     locality: end.name),
                              detail: end.detail))
        }
        return Array(items.prefix(limit))
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
