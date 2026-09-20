import Foundation
import CoreLocation

/// Предложенное место — ячейка, куда сходятся НАЧАЛА и КОНЦЫ своих поездок.
///
/// Место рождается из отметки (0.6.8), а отметка — ручное действие, о котором
/// человек с одной поездкой не знает. Поэтому вкладка сама показывает, где он
/// бывает: двор, от которого уезжают и к которому возвращаются, приложение
/// видит по уже записанному — без единого нового поля в базе.
///
/// Ячейка — та же `Place.cell` (geohash-7, ~150 м), и `id` считается тем же
/// `Place.id(forCell:)`: предложение и место, которое из него вырастет, — одна
/// и та же точка с одним и тем же id на всех телефонах.
struct PlaceSuggestion: Identifiable, Equatable {
    let cell: String
    /// Центроид попаданий, а не центр ячейки: уезжают от подъезда, а не из
    /// середины квадрата (то же правило, что у `Place.recomputeCentroid`).
    let latitude: Double
    let longitude: Double
    /// Сколько РАЗНЫХ поездок начиналось или заканчивалось здесь. Поездка
    /// голосует за ячейку один раз: круг по городу с возвратом во двор — это
    /// одна поездка, и строка «2 поездки» под ней была бы неправдой.
    let trips: Int
    /// Самая свежая из них — по ней разводятся равные счёта.
    let lastAt: Date
    /// Имя из кэша геокодера. Чистый счёт его не знает: кэш живёт в CoreData,
    /// а счёт идёт вне главного актёра — подставляет вью-модель.
    var name: String?

    var id: UUID { Place.id(forCell: cell) }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Чистый счёт предложений по превью библиотеки.
enum PlaceSuggestions {
    /// Больше пяти строк — это уже список дел, а не подсказка.
    static let limit = 5
    /// Обычный порог: два конца в одном дворе — это привычка, один — случай.
    static let minTrips = 2
    /// Библиотека меньше этой — порог падает до одного попадания. Иначе у
    /// человека с первой поездкой экран снова пуст, а он-то как раз и не
    /// знает, что места вообще бывают.
    static let smallLibrary = 5

    /// `previews` — лёгкие ссылки (`tripPreviews`), точки не поднимаются
    /// нигде: у предложения вопрос «откуда выехал и куда приехал», а на него
    /// отвечают первая и последняя точка превью.
    ///
    /// `taken` — id мест, которые предлагать нельзя: и живые (у них уже есть
    /// своя строка выше), и НАДГРОБИЯ — `placeId` отметок, чьё место удалили.
    /// Удалённое место не воскрешает ни сверка (правило 0.6.8), ни подсказка:
    /// человек уже сказал, что этой точки ему не надо.
    static func build(previews: [TripPreviewRef], taken: Set<UUID>) -> [PlaceSuggestion] {
        let threshold = previews.count < smallLibrary ? 1 : minTrips
        var buckets: [String: Bucket] = [:]
        for ref in previews {
            let coordinates = ref.previewCoordinates
            // Поездка без превью пропускается целиком — поднимать её точки
            // ради подсказки нельзя (то же правило, что у «Атласа»).
            guard let first = coordinates.first, let last = coordinates.last else { continue }
            var counted: Set<String> = []
            for end in [first, last] {
                let cell = Place.cell(latitude: end.latitude, longitude: end.longitude)
                guard counted.insert(cell).inserted else { continue }
                buckets[cell, default: Bucket()].add(end, at: ref.startDate)
            }
        }
        return buckets
            .compactMap { cell, bucket -> PlaceSuggestion? in
                guard bucket.trips >= threshold, !taken.contains(Place.id(forCell: cell)) else { return nil }
                return PlaceSuggestion(cell: cell,
                                       latitude: bucket.latitude / Double(bucket.trips),
                                       longitude: bucket.longitude / Double(bucket.trips),
                                       trips: bucket.trips, lastAt: bucket.lastAt)
            }
            // Третий ключ — ячейка: без него две равные подсказки меняются
            // местами от запуска к запуску (порядок словаря), и экран
            // перерисовывается «сам по себе».
            .sorted {
                if $0.trips != $1.trips { return $0.trips > $1.trips }
                if $0.lastAt != $1.lastAt { return $0.lastAt > $1.lastAt }
                return $0.cell < $1.cell
            }
            .prefix(limit)
            .map { $0 }
    }

    /// То же, но вне главного актёра: разбор превью всей библиотеки — это
    /// сотни тысяч координат у зрелого человека, а зовётся он с экрана.
    /// `Task.detached` — пока Swift 5.9 (см. CLAUDE.md «Performance»).
    static func buildDetached(previews: [TripPreviewRef], taken: Set<UUID>) async -> [PlaceSuggestion] {
        await Task.detached(priority: .utility) { build(previews: previews, taken: taken) }.value
    }

    private struct Bucket {
        var latitude = 0.0
        var longitude = 0.0
        var trips = 0
        var lastAt = Date.distantPast

        mutating func add(_ coordinate: CLLocationCoordinate2D, at date: Date) {
            latitude += coordinate.latitude
            longitude += coordinate.longitude
            trips += 1
            lastAt = max(lastAt, date)
        }
    }
}
