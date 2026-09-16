import Foundation
import CoreLocation

/// Веха, взятая на этом треке.
struct MilestoneHit: Equatable {
    let milestone: Milestone
    /// Ключ находки: `"<milestone>"` у вехи, которая бывает раз в жизни, и
    /// `"<milestone>:<regionId|cc-cc|yyyy-MM-dd>"` у остальных.
    let key: String
    /// Где именно веха случилась — туда и встанет печать.
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MilestoneHit, rhs: MilestoneHit) -> Bool {
        lhs.milestone == rhs.milestone
            && lhs.key == rhs.key
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

/// Вехи собственной географии: первый регион, самая восточная точка, два
/// километра высоты, граница.
///
/// Веха — это не награда и не значок: она про ЛИЧНУЮ карту человека, поэтому
/// всё, что тут считается, считается относительно его прошлых поездок
/// (`History`), а не относительно чужих рекордов. Чистая функция: истории
/// собирает вызывающий (волна 2, задача 4), здесь ни базы, ни `UserDefaults`.
///
/// **Ключ решает, повторится веха или нет.** «Первый регион» привязан к
/// региону, «граница» — к паре стран, экстремумы и ночной перевал — к дню:
/// самая восточная точка бывает новой каждый год, и веха обязана взяться
/// снова. А «выше двух километров» и «ниже уровня моря» ключа не имеют вовсе
/// — это раз в жизни, второй раз на том же перевале вехой уже не является.
/// Дальше по ключу выводится `Discovery.id`, и он же не даёт отметить одно и
/// то же дважды.
///
/// **Часовой пояс.** У `Trip` его нет — ни поля, ни колонки, — поэтому день
/// ключа и «ночь» считаются по ТЕКУЩЕМУ календарю телефона. Для поездки,
/// записанной дома, это правда; для поездки на другом конце страны, открытой
/// после возвращения, день может съехать на единицу. Цена ошибки — ключ, то
/// есть в худшем случае веха, взятая дважды за одни сутки; платить за это
/// колонкой в базе в 0.7.0 не стали.
enum MilestoneDetector {

    /// «Высоко» — две тысячи метров.
    static let alpineAltitude: Double = 2000
    /// «Ниже уровня моря». Минус метр, а не ноль: GPS шумит на несколько
    /// метров по высоте, и ноль сработал бы на любом морском берегу.
    static let belowSeaAltitude: Double = -1
    /// Ночной перевал — от полутора километров.
    static let nightAltitude: Double = 1500
    /// Ночь: с 22:00 до 05:00 местного времени.
    static let nightStartHour = 22
    static let nightEndHour = 5
    /// Столько разных регионов за одну поездку — уже веха.
    static let regionsInADay = 3

    /// Крайние точки собственной карты — по ПРЕДЫДУЩИМ поездкам.
    ///
    /// Каждая сторона отдельно опциональна: неизвестная сторона — это «мерить
    /// не от чего», и вехи она не даёт (первая поездка просто задаёт все
    /// четыре, молча).
    struct Extremes: Equatable {
        var north: CLLocationCoordinate2D?
        var south: CLLocationCoordinate2D?
        var east: CLLocationCoordinate2D?
        var west: CLLocationCoordinate2D?

        init(north: CLLocationCoordinate2D? = nil, south: CLLocationCoordinate2D? = nil,
             east: CLLocationCoordinate2D? = nil, west: CLLocationCoordinate2D? = nil) {
            self.north = north
            self.south = south
            self.east = east
            self.west = west
        }

        static func == (lhs: Extremes, rhs: Extremes) -> Bool {
            same(lhs.north, rhs.north) && same(lhs.south, rhs.south)
                && same(lhs.east, rhs.east) && same(lhs.west, rhs.west)
        }

        private static func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
            switch (a, b) {
            case (nil, nil): return true
            case let (x?, y?): return x.latitude == y.latitude && x.longitude == y.longitude
            default: return false
            }
        }
    }

    /// Что человек проехал ДО этой поездки.
    struct History {
        let visitedRegionIds: Set<String>
        /// Страны прошлых поездок. Ни одно правило 0.7.0 их не читает —
        /// поле стоит в контракте задачи как задел под «первая страна»
        /// (волна 3): считать его здесь сейчас значило бы придумать веху,
        /// которой нет ни в спеке, ни в значках.
        let visitedCountryCodes: Set<String>
        let extremes: Extremes?

        init(visitedRegionIds: Set<String> = [],
             visitedCountryCodes: Set<String> = [],
             extremes: Extremes? = nil) {
            self.visitedRegionIds = visitedRegionIds
            self.visitedCountryCodes = visitedCountryCodes
            self.extremes = extremes
        }
    }

    // MARK: - Разбор

    static func detect(trip: Trip, track: [TrackPoint], history: History, atlas: RegionAtlas) -> [MilestoneHit] {
        guard !track.isEmpty else { return [] }

        let day = dayKey(trip.startDate)
        var hits: [MilestoneHit] = []

        let geography = walk(track, atlas: atlas)

        // 1. Первый регион — по порядку появления на треке.
        for regionId in geography.regionOrder where !history.visitedRegionIds.contains(regionId) {
            guard let coordinate = geography.regionEntry[regionId] else { continue }
            hits.append(MilestoneHit(
                milestone: .firstRegion, key: "\(Milestone.firstRegion.rawValue):\(regionId)",
                coordinate: coordinate))
        }

        // 2. Экстремумы. Первая поездка (истории нет) не даёт ни одного:
        //    сравнивать не с чем, а объявить вехой сам факт первой поездки
        //    значило бы выдать сразу четыре печати за один выезд во двор.
        if let extremes = history.extremes {
            hits.append(contentsOf: self.extremes(track, beyond: extremes, day: day))
        }

        // 3. Высота.
        if let highest = track.max(by: { $0.altitude < $1.altitude }), highest.altitude >= alpineAltitude {
            hits.append(MilestoneHit(
                milestone: .above2000, key: Milestone.above2000.rawValue, coordinate: highest.coordinate))
        }
        if let lowest = track.min(by: { $0.altitude < $1.altitude }), lowest.altitude < belowSeaAltitude {
            hits.append(MilestoneHit(
                milestone: .belowSea, key: Milestone.belowSea.rawValue, coordinate: lowest.coordinate))
        }

        // 4. Три региона за поездку.
        if geography.regionOrder.count >= regionsInADay,
           let third = geography.regionEntry[geography.regionOrder[regionsInADay - 1]] {
            hits.append(MilestoneHit(
                milestone: .threeRegionsDay,
                key: "\(Milestone.threeRegionsDay.rawValue):\(day)", coordinate: third))
        }

        // 5. Граница: соседние РАЗРЕШЁННЫЕ точки трека в разных странах.
        //    Коды сортируются, чтобы «туда» и «обратно» дали один ключ.
        for crossing in geography.crossings {
            hits.append(MilestoneHit(
                milestone: .countryBorder,
                key: "\(Milestone.countryBorder.rawValue):\(crossing.key)",
                coordinate: crossing.coordinate))
        }

        // 6. Ночной перевал.
        if let night = nightPassPoint(track) {
            hits.append(MilestoneHit(
                milestone: .nightPass, key: "\(Milestone.nightPass.rawValue):\(day)",
                coordinate: night.coordinate))
        }

        return hits
    }

    // MARK: - География трека

    private struct Crossing {
        let key: String
        let coordinate: CLLocationCoordinate2D
    }

    private struct Geography {
        var regionOrder: [String] = []
        var regionEntry: [String: CLLocationCoordinate2D] = [:]
        var crossings: [Crossing] = []
    }

    /// Один проход по треку: регионы в порядке появления и пересечения границ.
    ///
    /// Точка вне атласа (море, страна без геометрии) не разрешается ни во что
    /// и в цепочку стран не попадает: иначе разрыв покрытия читался бы как
    /// выезд за границу и обратно.
    private static func walk(_ track: [TrackPoint], atlas: RegionAtlas) -> Geography {
        var geography = Geography()
        var previousIndex: Int?
        var lastCountry: (code: String, coordinate: CLLocationCoordinate2D)?
        var seenCrossings = Set<String>()

        for point in track {
            let coordinate = point.coordinate
            // Точки подряд почти всегда в одном регионе — тот же приём, что у
            // разбора территории: сначала пробуем прошлый.
            var index: Int?
            if let previousIndex, atlas.regionAtIndex(previousIndex, contains: coordinate) {
                index = previousIndex
            } else {
                index = atlas.regionIndex(containing: coordinate)
            }
            previousIndex = index
            guard let index, atlas.regions.indices.contains(index) else { continue }
            let region = atlas.regions[index]

            if geography.regionEntry[region.id] == nil {
                geography.regionEntry[region.id] = coordinate
                geography.regionOrder.append(region.id)
            }

            if let last = lastCountry, last.code != region.countryCode {
                let key = [last.code, region.countryCode].sorted().joined(separator: "-")
                if seenCrossings.insert(key).inserted {
                    geography.crossings.append(Crossing(
                        key: key, coordinate: midpoint(last.coordinate, coordinate)))
                }
            }
            lastCountry = (region.countryCode, coordinate)
        }
        return geography
    }

    private static func midpoint(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (a.latitude + b.latitude) / 2,
            longitude: (a.longitude + b.longitude) / 2)
    }

    // MARK: - Экстремумы

    private static func extremes(_ track: [TrackPoint], beyond base: Extremes, day: String) -> [MilestoneHit] {
        var hits: [MilestoneHit] = []

        func add(_ milestone: Milestone, _ point: TrackPoint?) {
            guard let point else { return }
            hits.append(MilestoneHit(
                milestone: milestone, key: "\(milestone.rawValue):\(day)", coordinate: point.coordinate))
        }

        if let north = base.north, let point = track.max(by: { $0.latitude < $1.latitude }),
           point.latitude > north.latitude { add(.northernmost, point) }
        if let south = base.south, let point = track.min(by: { $0.latitude < $1.latitude }),
           point.latitude < south.latitude { add(.southernmost, point) }
        // Долготу не сворачиваем через 180-й меридиан нарочно: поездку,
        // пересекающую антимеридиан, записать можно, а «восточнее» на ней не
        // определено вовсе — и врать числом хуже, чем промолчать.
        if let east = base.east, let point = track.max(by: { $0.longitude < $1.longitude }),
           point.longitude > east.longitude { add(.easternmost, point) }
        if let west = base.west, let point = track.min(by: { $0.longitude < $1.longitude }),
           point.longitude < west.longitude { add(.westernmost, point) }

        return hits
    }

    // MARK: - Ночь

    private static func nightPassPoint(_ track: [TrackPoint]) -> TrackPoint? {
        let calendar = Calendar.current
        return track
            .filter { $0.altitude >= nightAltitude }
            .filter {
                let hour = calendar.component(.hour, from: $0.timestamp)
                return hour >= nightStartHour || hour < nightEndHour
            }
            .max(by: { $0.altitude < $1.altitude })
    }

    // MARK: - День

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        // Часовой пояс — системный по умолчанию, и менять его после создания
        // нельзя: форматтер статический, а правка поля из двух потоков — это
        // гонка ради строки, которая и так считается по телефону.
        return formatter
    }()

    /// `yyyy-MM-dd` по календарю телефона — см. замечание про часовой пояс
    /// у самого типа.
    static func dayKey(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}
