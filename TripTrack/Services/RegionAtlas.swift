import Foundation
import CoreLocation
import os

private let regionAtlasLog = Logger(subsystem: "com.triptrack", category: "region-atlas")

/// Bundled administrative geometry for «Моя карта» — the «границы из
/// локального GeoJSON» the canon note asks for.
///
/// Ships as `MapRegions.json` (built by `Tools/build_map_regions.py` from
/// Natural Earth 1:10m admin-1, public domain, plus an open list of Russian
/// cities). Regions are federal subjects inside Russia and admin-1 units in
/// the countries you can actually drive to from here; everything else on
/// earth is out of scope and simply has no geometry.
///
/// Why geometry at all, when every trip already carries a geocoded `region`
/// string: that string is whatever Apple answered in whatever locale, it
/// exists only for places you have been, and it cannot be drawn. The atlas
/// gives the three things the canon screen is built on — a shape to fill, a
/// border to trace, and the regions you have NOT opened yet.
///
/// Lookups are by point-in-polygon, never by name, so a trip lands in the
/// right subject regardless of how the geocoder spelled it.
final class RegionAtlas {
    static let shared = RegionAtlas()

    struct Region {
        let id: String              // ISO 3166-2, e.g. "RU-KDA"
        let countryCode: String     // "RU"
        let nameRu: String
        let nameEn: String
        let center: CLLocationCoordinate2D
        let bounds: GeoBounds
        /// Outer rings, flat [lat, lon, lat, lon, …]. Flat storage keeps the
        /// 35 000-vertex atlas out of per-coordinate allocations, which is
        /// what makes point-in-polygon cheap enough to run per track point.
        let rings: [[Double]]

        func localizedName(_ language: LanguageManager.Language) -> String {
            language == .ru ? nameRu : nameEn
        }
    }

    /// Country outline — geometry only, no lookups. `RegionPathIndex`
    /// (0.7.0, `RegionAtlas.countries`) uses these rings to draw a border
    /// for every country on earth at world zoom; `regions` above still
    /// carries the point-in-polygon detail for the 20 driveable countries.
    struct MapCountry {
        let id: String
        let nameRu: String
        let nameEn: String
        let center: CLLocationCoordinate2D
        let bounds: GeoBounds
        /// Outer rings, flat [lat, lon, lat, lon, …]. Empty for a country
        /// whose ring fell under the build script's span floor (micro-
        /// states) — it still has a `center`/`bounds` for a label anchor
        /// and LOD sizing, just nothing to trace.
        let rings: [[Double]]

        func localizedName(_ language: LanguageManager.Language) -> String {
            language == .ru ? nameRu : nameEn
        }
    }

    struct City {
        let name: String
        let nameEn: String
        let regionId: String
        let coordinate: CLLocationCoordinate2D
        let population: Int

        func localizedName(_ language: LanguageManager.Language) -> String {
            language == .ru ? name : nameEn
        }

        /// How far out of the centre the city still counts as "here". A
        /// million-plus city sprawls; a 12 000-person town does not.
        var radiusMeters: Double {
            switch population {
            case 1_000_000...: return 20_000
            case 250_000...:   return 12_000
            case 50_000...:    return 8_000
            default:           return 5_000
            }
        }
    }

    private(set) var regions: [Region] = []
    private(set) var citiesByRegion: [String: [City]] = [:]
    private(set) var countryNames: [String: (ru: String, en: String)] = [:]
    /// Every country on earth with usable admin-0 geometry (0.7.0) — for
    /// drawing, not for lookups. `country(containing:)` does not exist:
    /// nothing needs it, `region(containing:)` already answers "which
    /// country" via `Region.countryCode` for the 20 driveable ones, and
    /// the other ~220 only ever get drawn, never matched against a track.
    private(set) var countries: [MapCountry] = []
    private(set) var isLoaded = false

    /// Region indices bucketed by whole-degree cell, so a lookup tests two or
    /// three polygons instead of six hundred.
    private var grid: [Int: [Int]] = [:]
    private var regionIndexById: [String: Int] = [:]
    /// Для каждого региона — индексы регионов МЕНЬШЕЙ рамки, чья рамка его
    /// задевает. Считается один раз при разборе бандла.
    ///
    /// Нужен быстрому пути (`regionAtIndex(_:contains:)`), и нужен именно
    /// СПИСКОМ, а не походом в сетку: правило анклава добавляет ему работу на
    /// каждой точке трека, а точек в разборе финиша сотни тысяч. У
    /// подавляющего большинства регионов список пуст, и тогда быстрый путь
    /// стоит ровно столько же, сколько стоил до правила.
    private var enclaves: [[Int]] = []
    private var loadTask: Task<Void, Never>?

    private init() {}

    // MARK: - Loading

    /// Parses the atlas once, off the main actor, then publishes it on main.
    /// Concurrent callers share the same task. Everything below is read-only
    /// after that, which is what lets the background attribution loop touch
    /// the atlas without locking.
    @MainActor
    func loadIfNeeded() async {
        if isLoaded { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { @MainActor in
            let parsed = await Task.detached(priority: .userInitiated) {
                RegionAtlas.parseBundle()
            }.value
            if let parsed { self.install(parsed) }
        }
        loadTask = task
        await task.value
    }

    @MainActor
    private func install(_ parsed: Parsed) {
        regions = parsed.regions
        citiesByRegion = parsed.citiesByRegion
        countryNames = parsed.countryNames
        countries = parsed.countries
        grid = parsed.grid
        regionIndexById = parsed.regionIndexById
        enclaves = parsed.enclaves
        isLoaded = true
        loadTask = nil
    }

    // MARK: - Lookups

    func region(id: String) -> Region? {
        guard let index = regionIndexById[id] else { return nil }
        return regions[index]
    }

    /// The region a coordinate falls inside, or nil out at sea / outside the
    /// bundled countries.
    func region(containing coordinate: CLLocationCoordinate2D) -> Region? {
        guard let index = regionIndex(containing: coordinate) else { return nil }
        return regions[index]
    }

    /// Index form — used by the per-track-point attribution loop, which runs
    /// hundreds of thousands of times and must not build structs.
    ///
    /// **Правило анклава: из нескольких накрывших точку регионов побеждает
    /// тот, у кого рамка МЕНЬШЕ.** Natural Earth отдаёт Краснодарский край
    /// сплошным кольцом, без дырки под Адыгеей, — и до этого правила Майкоп
    /// отвечал «Краснодарский край» просто потому, что край лежал в ячейке
    /// сетки раньше. Ответ зависел от порядка строк в бандле, то есть был
    /// случайным; километры и «посещённые регионы» доставались обёртке, а не
    /// анклаву. Вложенные регионы различает только площадь: анклав по
    /// определению меньше того, внутри чего он лежит.
    func regionIndex(containing coordinate: CLLocationCoordinate2D) -> Int? {
        let lat = coordinate.latitude, lon = coordinate.longitude
        guard let candidates = grid[Self.cellKey(lat: lat, lon: lon)] else { return nil }
        // Кандидаты в ячейке лежат ПО ВОЗРАСТАНИЮ площади рамки (сортируются
        // при разборе бандла), поэтому первое же попадание и есть самое
        // мелкое — цикл не стал дороже, чем был до правила анклава.
        for index in candidates {
            let region = regions[index]
            guard region.bounds.contains(coordinate) else { continue }
            if Self.contains(lat: lat, lon: lon, rings: region.rings) { return index }
        }
        return nil
    }

    /// Same test against one known region — the attribution loop tries the
    /// previous point's region first, and consecutive GPS points almost
    /// always share it.
    ///
    /// Быстрый путь обязан отвечать ТО ЖЕ, что и полный поиск, иначе правило
    /// анклава живёт в одном резолвере из двух и Майкоп получает край или
    /// республику в зависимости от того, откуда приехала предыдущая точка.
    /// Поэтому «да» здесь значит «и никакой МЕНЬШИЙ регион эту точку не
    /// накрывает»; кандидаты с рамкой не меньше отбрасываются сравнением, и
    /// лишний луч по кольцу платится только у настоящего анклава.
    func regionAtIndex(_ index: Int, contains coordinate: CLLocationCoordinate2D) -> Bool {
        guard regions.indices.contains(index) else { return false }
        let region = regions[index]
        guard region.bounds.contains(coordinate),
              Self.contains(lat: coordinate.latitude, lon: coordinate.longitude,
                            rings: region.rings) else { return false }
        guard enclaves.indices.contains(index) else { return true }
        for other in enclaves[index] {
            let smaller = regions[other]
            guard smaller.bounds.contains(coordinate),
                  Self.contains(lat: coordinate.latitude, lon: coordinate.longitude,
                                rings: smaller.rings) else { continue }
            return false
        }
        return true
    }

    func cities(in regionId: String) -> [City] { citiesByRegion[regionId] ?? [] }

    func countryName(_ code: String, _ language: LanguageManager.Language) -> String? {
        guard let entry = countryNames[code] else { return nil }
        return language == .ru ? entry.ru : entry.en
    }

    /// 🇷🇺 from "RU" — regional-indicator arithmetic, no asset needed.
    static func flag(for countryCode: String) -> String {
        let base: UInt32 = 127_397
        var result = ""
        for scalar in countryCode.uppercased().unicodeScalars {
            guard let composed = UnicodeScalar(base + scalar.value) else { continue }
            result.unicodeScalars.append(composed)
        }
        return result
    }

    // MARK: - Geometry

    /// Ray casting over flat rings. Rings that model a donut (Moscow Oblast
    /// around Moscow) arrive pre-cut with a slit, so plain XOR is correct.
    static func contains(lat: Double, lon: Double, rings: [[Double]]) -> Bool {
        var inside = false
        for ring in rings {
            // `withUnsafeBufferPointer` — the 0.7.0 atlas tolerance roughly
            // doubles the average ring's vertex count (§3.3), and this loop
            // runs per sampled track point; bounds-checked `[Double]`
            // subscripting was measurably the difference between a finish
            // screen that waits and one that doesn't
            // (`DiscoveryProcessorTests.testHistoryOverAThousandTripsIsWalkedOnceAndCheaply`).
            // Same ray-casting math, just without the per-access check.
            ring.withUnsafeBufferPointer { buffer in
                let count = buffer.count / 2
                guard count > 2 else { return }
                var j = count - 1
                for i in 0..<count {
                    let yi = buffer[2 * i], xi = buffer[2 * i + 1]
                    let yj = buffer[2 * j], xj = buffer[2 * j + 1]
                    if (yi > lat) != (yj > lat) {
                        let crossing = (xj - xi) * (lat - yi) / (yj - yi) + xi
                        if lon < crossing { inside.toggle() }
                    }
                    j = i
                }
            }
        }
        return inside
    }

    private static func cellKey(lat: Double, lon: Double) -> Int {
        // 2° cells: coarse enough that the grid itself stays small, fine
        // enough that a cell rarely holds more than a handful of regions.
        let la = Int((lat / 2).rounded(.down)) + 90
        let lo = Int((lon / 2).rounded(.down)) + 180
        return la &* 1000 &+ lo
    }

    // MARK: - Parsing (off-main, value types only)

    /// Internal, not private: `parse(data:)` below is a test seam, and its
    /// return type has to be visible to `@testable import` for a test to
    /// read it back.
    struct Parsed {
        let regions: [Region]
        let citiesByRegion: [String: [City]]
        let countryNames: [String: (ru: String, en: String)]
        let countries: [MapCountry]
        let grid: [Int: [Int]]
        let regionIndexById: [String: Int]
        let enclaves: [[Int]]
    }

    private struct Payload: Decodable {
        /// Names are optional on purpose: one unnamed row in the source
        /// data must not take the whole atlas down with it.
        struct RawRegion: Decodable {
            let id: String
            let cc: String
            let ru: String?
            let en: String?
            let c: [Double]
            let b: [Double]
            let r: [[Double]]
        }
        struct RawCountry: Decodable {
            let id: String
            let ru: String
            let en: String
            let c: [Double]
            let b: [Double]
            /// Optional (0.7.0): a country whose ring fell under the build
            /// script's span floor ships without `r` at all. `JSONDecoder`
            /// fails an entire array on one bad element, so this being
            /// non-optional would let ONE tiny-country row take every
            /// country — and every region and city alongside it, since
            /// they all decode as one `Payload` — down with it.
            let r: [[Double]]?
        }
        struct RawCity: Decodable {
            let n: String
            /// English name — a real one where Natural Earth knows the place
            /// («Moscow»), transliterated otherwise.
            let e: String?
            let r: String
            let c: [Double]
            let p: Int
        }
        let regions: [RawRegion]
        let countries: [RawCountry]
        let cities: [RawCity]
    }

    /// The atlas ships with the app, but unit tests run in their own bundle,
    /// so resolve by the class's own bundle first and only then fall back to
    /// `Bundle.main`.
    private static func atlasURL() -> URL? {
        var candidates = [Bundle(for: RegionAtlas.self), Bundle.main]
        // Under `xcodebuild test` the app's code is loaded from a dylib whose
        // bundle is neither of the two above, so sweep the rest as a fallback.
        candidates.append(contentsOf: Bundle.allBundles)
        candidates.append(contentsOf: Bundle.allFrameworks)
        for bundle in candidates {
            if let url = bundle.url(forResource: "MapRegions", withExtension: "json") {
                return url
            }
        }
        return nil
    }

    /// Never fatal: a map without borders is a worse map, not a dead app —
    /// the screen falls back to routes and trip pins only. The failure paths
    /// are kept apart because they were once collapsed into one `guard`, and
    /// a single nameless row in the data read as «file not found» for hours.
    private static func parseBundle() -> Parsed? {
        guard let url = atlasURL() else {
            print("[RegionAtlas] MapRegions.json not found in any bundle")
            return nil
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            print("[RegionAtlas] cannot read \(url.lastPathComponent)")
            return nil
        }
        return parse(data: data)
    }

    /// Split from `parseBundle()` so a test can feed synthetic JSON — a
    /// duplicate `id` in the bundle is rare enough that the real
    /// `MapRegions.json` will likely never exercise this path, and the
    /// dedup guard below deserves its own coverage independent of that.
    static func parse(data: Data) -> Parsed? {
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            print("[RegionAtlas] decode failed: \(error)")
            return nil
        }

        var regions: [Region] = []
        var grid: [Int: [Int]] = [:]
        var indexById: [String: Int] = [:]
        regions.reserveCapacity(payload.regions.count)

        for raw in payload.regions {
            guard raw.b.count == 4, raw.c.count == 2,
                  let ru = raw.ru, let en = raw.en, !ru.isEmpty else { continue }
            // A silent `indexById[raw.id] = index` overwrite once let a
            // duplicate row hide a region from every lookup while its
            // orphaned bbox kept polluting `grid` (0.7.0 fix-up). The first
            // row wins and the rest are dropped — the same "don't fabricate,
            // don't silently prefer the last" instinct as everywhere else in
            // this file, just enforced at parse time instead of only in the
            // build script.
            guard indexById[raw.id] == nil else {
                regionAtlasLog.error("duplicate region id in MapRegions.json, keeping first: \(raw.id, privacy: .public)")
                continue
            }
            let index = regions.count
            regions.append(Region(
                id: raw.id,
                countryCode: raw.cc,
                nameRu: ru,
                nameEn: en,
                center: CLLocationCoordinate2D(latitude: raw.c[0], longitude: raw.c[1]),
                bounds: GeoBounds(minLat: raw.b[0], maxLat: raw.b[2], minLon: raw.b[1], maxLon: raw.b[3]),
                rings: raw.r
            ))
            indexById[raw.id] = index

            var lat = (raw.b[0] / 2).rounded(.down) * 2
            while lat <= raw.b[2] {
                var lon = (raw.b[1] / 2).rounded(.down) * 2
                while lon <= raw.b[3] {
                    grid[cellKey(lat: lat, lon: lon), default: []].append(index)
                    lon += 2
                }
                lat += 2
            }
        }

        // Ячейки сортируются по площади рамки: правило анклава после этого —
        // просто «первое попадание», без второго прохода и без сравнения
        // площадей в цикле по точкам трека.
        for key in grid.keys {
            grid[key]?.sort { regions[$0].bounds.area < regions[$1].bounds.area }
        }
        // Кто в кого может быть вложен — ПО ЯЧЕЙКАМ СЕТКИ, а не парами по всем
        // регионам. Вложенные обязаны делить хотя бы одну ячейку, а в ячейке
        // их два-три; полный перебор 606 × 606 стоил бы под сотню
        // миллисекунд отладочной сборки прямо в загрузке атласа, и первый же
        // финиш поездки заплатил бы их на экране итогов.
        var nested = [Set<Int>](repeating: [], count: regions.count)
        for bucket in grid.values where bucket.count > 1 {
            for outer in bucket {
                let big = regions[outer].bounds
                let area = big.area
                for inner in bucket where inner != outer {
                    let small = regions[inner].bounds
                    guard small.area < area, small.intersects(big) else { continue }
                    nested[outer].insert(inner)
                }
            }
        }
        let enclaves = nested.map(Array.init)

        var citiesByRegion: [String: [City]] = [:]
        for raw in payload.cities where raw.c.count == 2 {
            citiesByRegion[raw.r, default: []].append(City(
                name: raw.n,
                nameEn: raw.e ?? raw.n,
                regionId: raw.r,
                coordinate: CLLocationCoordinate2D(latitude: raw.c[0], longitude: raw.c[1]),
                population: raw.p
            ))
        }
        for key in citiesByRegion.keys {
            citiesByRegion[key]?.sort { $0.population > $1.population }
        }

        var countryNames: [String: (ru: String, en: String)] = [:]
        var countries: [MapCountry] = []
        countries.reserveCapacity(payload.countries.count)
        for raw in payload.countries {
            countryNames[raw.id] = (raw.ru, raw.en)
            guard raw.c.count == 2, raw.b.count == 4 else { continue }
            countries.append(MapCountry(
                id: raw.id,
                nameRu: raw.ru,
                nameEn: raw.en,
                center: CLLocationCoordinate2D(latitude: raw.c[0], longitude: raw.c[1]),
                bounds: GeoBounds(minLat: raw.b[0], maxLat: raw.b[2], minLon: raw.b[1], maxLon: raw.b[3]),
                rings: raw.r ?? []
            ))
        }

        return Parsed(
            regions: regions,
            citiesByRegion: citiesByRegion,
            countryNames: countryNames,
            countries: countries,
            grid: grid,
            regionIndexById: indexById,
            enclaves: enclaves
        )
    }
}
