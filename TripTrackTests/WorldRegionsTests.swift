import CoreLocation
import XCTest
@testable import TripTrack

/// Regions for the whole world (0.9.0). Owner, 13 Oct 2026: «регионы надо
/// добавить максимально все». Until then only twenty countries had regions,
/// and a driver in Germany, Spain, the US or France — the first storefronts by
/// downloads — saw «0 регионов» on the atlas, the stats and public maps.
final class WorldRegionsTests: XCTestCase {
    private var atlas: RegionAtlas!

    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
        atlas = RegionAtlas.shared
        try XCTSkipUnless(atlas.isLoaded, "MapRegions.json missing from the test bundle")
    }

    func testDriversOutsideTheOriginalTwentyGetARegion() {
        let cases: [(String, CLLocationCoordinate2D)] = [
            ("DE", CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575)),   // München
            ("ES", CLLocationCoordinate2D(latitude: 40.417, longitude: -3.704)),   // Madrid
            ("US", CLLocationCoordinate2D(latitude: 34.052, longitude: -118.244)), // Los Angeles
            ("FR", CLLocationCoordinate2D(latitude: 48.857, longitude: 2.352)),    // Paris
            ("IT", CLLocationCoordinate2D(latitude: 41.903, longitude: 12.496)),   // Roma
            ("GB", CLLocationCoordinate2D(latitude: 51.507, longitude: -0.128)),   // London
            ("CA", CLLocationCoordinate2D(latitude: 43.653, longitude: -79.383)),  // Toronto
            ("AU", CLLocationCoordinate2D(latitude: -33.869, longitude: 151.209)), // Sydney
            ("IN", CLLocationCoordinate2D(latitude: 28.614, longitude: 77.209)),   // Delhi
            ("UG", CLLocationCoordinate2D(latitude: 0.347, longitude: 32.582)),    // Kampala
        ]
        for (cc, point) in cases {
            XCTAssertEqual(atlas.region(containing: point)?.countryCode, cc, "\(cc) \(point)")
        }
    }

    /// The original twenty keep their ids — people's visited regions and
    /// kilometres per region are stored under them.
    func testOriginalRegionsKeepTheirIds() {
        let kept: [(String, CLLocationCoordinate2D)] = [
            ("RU-KDA", CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)),
            ("RU-AD", CLLocationCoordinate2D(latitude: 44.6098, longitude: 40.1006)),
            ("GE-AJ", CLLocationCoordinate2D(latitude: 41.82, longitude: 41.78)),
            ("RU-MOW", CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173)),
        ]
        for (id, point) in kept { XCTAssertEqual(atlas.region(containing: point)?.id, id) }
    }

    func testRegionNamesFollowTheAppLanguage() throws {
        let bavaria = try XCTUnwrap(atlas.region(containing: CLLocationCoordinate2D(latitude: 48.137, longitude: 11.575)))
        XCTAssertEqual(bavaria.localizedName(.en), "Bavaria")
        XCTAssertEqual(bavaria.localizedName(.de), "Bayern")
        XCTAssertEqual(bavaria.localizedName(.ru), "Бавария")
        // No Kazakh column in Natural Earth — English, not an invented name.
        XCTAssertEqual(bavaria.localizedName(.kk), "Bavaria")
    }

    func testBundleWithoutLocalNamesStillParses() throws {
        let json = #"{"v":2,"regions":[{"id":"XX-A","cc":"XX","ru":"Р","en":"E","c":[1,1],"b":[0,0,2,2],"r":[[0,0,0,2,2,2,2,0]]}],"countries":[],"cities":[]}"#
        let parsed = try XCTUnwrap(RegionAtlas.parse(data: Data(json.utf8)))
        XCTAssertEqual(parsed.regions.first?.localizedName(.de), "E")
    }

    /// The atlas is parsed once, off the main actor, before the first map
    /// (`loadIfNeeded`). The world bundle is ~7 MB of JSON; this is the time
    /// a person waits for regions on a cold launch.
    func testParsingTheWorldBundleStaysQuick() throws {
        let candidates = [Bundle(for: RegionAtlas.self), Bundle.main] + Bundle.allBundles
        let url = try XCTUnwrap(candidates.lazy.compactMap { $0.url(forResource: "MapRegions", withExtension: "json") }.first)
        let data = try Data(contentsOf: url)
        var best = Double.infinity
        for _ in 0..<3 {
            let start = CFAbsoluteTimeGetCurrent()
            XCTAssertNotNil(RegionAtlas.parse(data: data))
            best = min(best, CFAbsoluteTimeGetCurrent() - start)
        }
        print("PROBE world parse: \(data.count / 1024) KB in \(String(format: "%.0f", best * 1000)) ms")
        XCTAssertLessThan(best, 3.0)
    }

    /// Per-point lookup runs for every track point of every trip; the world
    /// bundle must not make it slower in a way a person would feel.
    func testLookupStaysFastWithTheWorldBundle() {
        var points: [CLLocationCoordinate2D] = []
        for i in 0..<20_000 {
            let t = Double(i) / 20_000
            points.append(CLLocationCoordinate2D(latitude: 44 + t * 12, longitude: 38 + t * 2))   // Russia
            points.append(CLLocationCoordinate2D(latitude: 47.5 + t * 6, longitude: 7 + t * 7))   // Germany
        }
        let start = CFAbsoluteTimeGetCurrent()
        var hits = 0
        for p in points where atlas.regionIndex(containing: p) != nil { hits += 1 }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        print("PROBE world lookup: \(points.count) points in \(String(format: "%.0f", ms)) ms, hits=\(hits)")
        XCTAssertGreaterThan(hits, points.count * 9 / 10)
        XCTAssertLessThan(ms, 2_000)
    }
}
