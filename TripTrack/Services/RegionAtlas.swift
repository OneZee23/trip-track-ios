import Foundation
import CoreLocation

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
    private(set) var isLoaded = false

    /// Region indices bucketed by whole-degree cell, so a lookup tests two or
    /// three polygons instead of six hundred.
    private var grid: [Int: [Int]] = [:]
    private var regionIndexById: [String: Int] = [:]
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
        grid = parsed.grid
        regionIndexById = parsed.regionIndexById
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
    func regionIndex(containing coordinate: CLLocationCoordinate2D) -> Int? {
        let lat = coordinate.latitude, lon = coordinate.longitude
        guard let candidates = grid[Self.cellKey(lat: lat, lon: lon)] else { return nil }
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
    func regionAtIndex(_ index: Int, contains coordinate: CLLocationCoordinate2D) -> Bool {
        guard regions.indices.contains(index) else { return false }
        let region = regions[index]
        guard region.bounds.contains(coordinate) else { return false }
        return Self.contains(lat: coordinate.latitude, lon: coordinate.longitude, rings: region.rings)
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
            let count = ring.count / 2
            guard count > 2 else { continue }
            var j = count - 1
            for i in 0..<count {
                let yi = ring[2 * i], xi = ring[2 * i + 1]
                let yj = ring[2 * j], xj = ring[2 * j + 1]
                if (yi > lat) != (yj > lat) {
                    let crossing = (xj - xi) * (lat - yi) / (yj - yi) + xi
                    if lon < crossing { inside.toggle() }
                }
                j = i
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

    private struct Parsed {
        let regions: [Region]
        let citiesByRegion: [String: [City]]
        let countryNames: [String: (ru: String, en: String)]
        let grid: [Int: [Int]]
        let regionIndexById: [String: Int]
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
        for raw in payload.countries { countryNames[raw.id] = (raw.ru, raw.en) }

        return Parsed(
            regions: regions,
            citiesByRegion: citiesByRegion,
            countryNames: countryNames,
            grid: grid,
            regionIndexById: indexById
        )
    }
}
