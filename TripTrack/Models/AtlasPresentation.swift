import Foundation
import CoreLocation

/// The dates constrain the trips shown on the atlas. A custom end date is
/// inclusive for the entire calendar day; relative periods follow local time.
enum AtlasPeriod: Equatable {
    case allTime
    case thisYear
    case last30Days
    case custom(start: Date, end: Date)

    func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .allTime:
            return nil
        case .thisYear:
            return calendar.dateInterval(of: .year, for: now)
        case .last30Days:
            let today = calendar.startOfDay(for: now)
            guard let start = calendar.date(byAdding: .day, value: -29, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: today) else { return nil }
            return DateInterval(start: start, end: end)
        case .custom(let start, let end):
            let first = calendar.startOfDay(for: min(start, end))
            let last = calendar.startOfDay(for: max(start, end))
            guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
            return DateInterval(start: first, end: exclusiveEnd)
        }
    }

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let interval = interval(now: now, calendar: calendar) else { return true }
        return date >= interval.start && date < interval.end
    }
}

struct AtlasMapAppearance: Equatable, Codable {
    /// `cells` — третий стиль (0.8.2): тот же светлый туман, но открытое в
    /// нём квантовано клетками (`FogCellGrid`). Палитру он делит с `fog` —
    /// от `night` отличается только мгла, а от `fog` только сетка.
    /// `rawValue` менять нельзя: это `UserDefaults` на телефоне.
    enum Style: String, CaseIterable, Codable { case fog, night, cells }

    /// Мгла тёмная только у «Ночи». Отдельным свойством, а не сравнением по
    /// месту: третий стиль уже показал, что таких сравнений набирается
    /// несколько и они разъезжаются.
    var usesDarkFog: Bool { style == .night }
    /// Открытое рисуется клетками.
    var usesCells: Bool { style == .cells }

    var style: Style = .fog
    var showsPhotos = true

    private static let defaultsKey = "atlas.mapAppearance"
    static var saved: AtlasMapAppearance { load() }

    static func load(defaults: UserDefaults = .standard) -> AtlasMapAppearance {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Prepares the overview once per exploration snapshot, outside SwiftUI's
/// drag and search rendering passes. City names are not globally unique.
struct AtlasOverviewIndex {
    struct City: Identifiable {
        let id: String
        let regionID: String
        let stat: MapCityStat
        let wasVisited: Bool

        var isVisited: Bool { stat.coverage > 0 }
        var coordinate: CLLocationCoordinate2D { stat.coordinate }
        func localizedName(_ language: LanguageManager.Language) -> String {
            stat.localizedName(language)
        }
    }

    struct SearchRegion: Identifiable {
        let region: RegionAtlas.Region
        let visited: MapRegionStat?
        let wasVisited: Bool
        var id: String { region.id }
        var isVisited: Bool { visited != nil }
    }

    struct Country: Identifiable {
        let id: String
        let regions: [MapRegionStat]
        let drivenKm: Double
    }

    struct SearchResults {
        let countries: [Country]
        let cities: [City]
        let regions: [SearchRegion]
        var isEmpty: Bool { countries.isEmpty && cities.isEmpty && regions.isEmpty }
    }

    let countries: [Country]
    let tripsByDate: [MapTripPin]
    private let russianCities: [City]
    private let internationalCities: [City]
    private let catalogCities: [City]
    private let catalogRegions: [SearchRegion]

    static let empty = AtlasOverviewIndex(exploration: MapExploration())
    var cityCount: Int { russianCities.count }

    func cities(language: LanguageManager.Language) -> [City] {
        language == .ru ? russianCities : internationalCities
    }

    func search(_ query: String, language: LanguageManager.Language) -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return SearchResults(countries: countries, cities: cities(language: language), regions: [])
        }
        func matches(_ name: String) -> Bool {
            name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive],
                       locale: language.locale) != nil
        }
        let foundRegions = catalogRegions.filter { matches($0.region.localizedName(language)) }
            .sorted {
                if $0.isVisited != $1.isVisited { return $0.isVisited }
                let a = $0.region.localizedName(language), b = $1.region.localizedName(language)
                return a == b ? $0.id < $1.id : a < b
            }
        let foundCities = catalogCities.filter { matches($0.localizedName(language)) }
            .sorted {
                if $0.isVisited != $1.isVisited { return $0.isVisited }
                let a = $0.localizedName(language), b = $1.localizedName(language)
                return a == b ? $0.id < $1.id : a < b
            }
        return SearchResults(countries: [], cities: foundCities, regions: foundRegions)
    }

    init(exploration: MapExploration, catalogRegions: [RegionAtlas.Region] = [],
         catalogCities: [RegionAtlas.City] = [], historical: MapExploration? = nil) {
        countries = Dictionary(grouping: exploration.regions, by: \.countryCode)
            .map { code, regions in
                Country(id: code, regions: regions, drivenKm: regions.reduce(0) { $0 + $1.km })
            }
            .sorted { $0.drivenKm == $1.drivenKm ? $0.id < $1.id : $0.drivenKm > $1.drivenKm }
        tripsByDate = exploration.trips.sorted {
            $0.startDate == $1.startDate
                ? $0.id.uuidString < $1.id.uuidString : $0.startDate > $1.startDate
        }
        func cityID(region: String, name: String, coordinate: CLLocationCoordinate2D) -> String {
            "\(region):\(name):\(coordinate.latitude):\(coordinate.longitude)"
        }
        let historical = historical ?? exploration
        let historicalCityIDs = Set(historical.regions.flatMap { region in
            region.cities.filter { $0.coverage > 0 }.map {
                cityID(region: region.id, name: $0.name, coordinate: $0.coordinate)
            }
        })
        var cityIndex: [String: City] = [:]
        for region in exploration.regions {
            for city in region.cities where city.coverage > 0 {
                let id = cityID(region: region.id, name: city.name, coordinate: city.coordinate)
                cityIndex[id] = City(id: id, regionID: region.id, stat: city, wasVisited: true)
            }
        }
        let cities = Array(cityIndex.values)
        russianCities = cities.sorted {
            let a = $0.localizedName(.ru), b = $1.localizedName(.ru)
            return a == b ? $0.id < $1.id : a < b
        }
        internationalCities = cities.sorted {
            let a = $0.localizedName(.en), b = $1.localizedName(.en)
            return a == b ? $0.id < $1.id : a < b
        }
        for city in catalogCities {
            let id = cityID(region: city.regionId, name: city.name, coordinate: city.coordinate)
            guard cityIndex[id] == nil else { continue }
            cityIndex[id] = City(id: id, regionID: city.regionId,
                stat: MapCityStat(name: city.name, nameEn: city.nameEn,
                                  coordinate: city.coordinate, coverage: 0),
                wasVisited: historicalCityIDs.contains(id))
        }
        self.catalogCities = Array(cityIndex.values)

        let visitedByID = Dictionary(uniqueKeysWithValues: exploration.regions.map { ($0.id, $0) })
        let historicalRegionIDs = Set(historical.regions.map(\.id))
        var regionIndex = Dictionary(uniqueKeysWithValues: catalogRegions.map { ($0.id, $0) })
        for region in exploration.regions where regionIndex[region.id] == nil {
            regionIndex[region.id] = RegionAtlas.Region(
                id: region.id, countryCode: region.countryCode, nameRu: region.nameRu,
                nameEn: region.nameEn, center: region.center, bounds: region.bounds, rings: [])
        }
        self.catalogRegions = regionIndex.values.map {
            SearchRegion(region: $0, visited: visitedByID[$0.id],
                         wasVisited: historicalRegionIDs.contains($0.id))
        }
    }
}

/// A temporary, deduplicated view of the roads driven in a chosen period.
/// This uses the same preview geometry and claiming rules as the persistent
/// atlas, but never writes into its cells or reads raw tracking points.
enum AtlasPreviewLayer {
    static func build(trips: [Trip], atlas: RegionAtlas?) -> RevealedLayer {
        var claimed: [String: Set<RevealGrid.Cell>] = [:]
        var runs: [[CLLocationCoordinate2D]] = []
        for trip in trips.sorted(by: {
            $0.startDate == $1.startDate
                ? $0.id.uuidString < $1.id.uuidString
                : $0.startDate < $1.startDate
        }) {
            guard trip.previewPolyline?.isEmpty == false else { continue }
            let coordinates = trip.previewCoordinates
            guard coordinates.count > 1 else { continue }
            let patches = RevealBuilder.patches(for: coordinates) { claimed[$0] ?? [] }
            for (key, patch) in patches {
                claimed[key, default: []].formUnion(patch.cells)
                runs.append(contentsOf: patch.runs)
            }
        }
        return RevealedLayer.build(
            runs: runs, cellCount: claimed.values.reduce(0) { $0 + $1.count }, atlas: atlas)
    }
}

/// Границы календаря «своего периода» — чистой функцией, как
/// `JourneyEditSheet.startBounds`: собрать `ClosedRange` из двух дат можно
/// только так, чтобы перевернуть его было НЕЛЬЗЯ (`a...b` при `a > b` роняет
/// процесс, а не отдаёт пустоту), и проверяться это обязано тестом, а не
/// открытым на телефоне экраном.
///
/// Верх у обеих границ — СЕГОДНЯ: поездок из будущего не бывает, и выбирать
/// их даты незачем. До 0.8.1 конец окна брался из `start...Date
/// .distantFuture`, то есть окно можно было увести вперёд на века. Нижнюю
/// границу не трогаем: библиотека бывает какой угодно старой.
enum AtlasPeriodBounds {
    /// Начало: до КОНЦА окна, но не в будущее.
    static func start(start: Date, end: Date, now: Date = Date()) -> ClosedRange<Date> {
        Date.distantPast...min(end, now)
    }

    /// Конец: от начала окна до сегодня.
    static func end(start: Date, end: Date, now: Date = Date()) -> ClosedRange<Date> {
        min(start, now)...now
    }

    /// Окно, пришедшее откуда угодно, приведённое к допустимому: порядок
    /// нормализован, будущее срезано.
    static func clamp(start: Date, end: Date, now: Date = Date()) -> (start: Date, end: Date) {
        let a = min(start, end), b = max(start, end)
        let clampedEnd = min(b, now)
        return (min(a, clampedEnd), clampedEnd)
    }
}
