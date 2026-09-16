import XCTest
import CoreLocation
@testable import TripTrack

/// Regression tests for the bundled `MapRegions.json` itself, not just the
/// parser that reads it (`MyMapAtlasTests` covers that side). These pin the
/// data `Tools/build_map_regions.py` is supposed to produce — a budget, a
/// world-wide country list, and the hit vectors that would have caught the
/// «Батуми → Кобулети за кольцом GE-AJ» bug before it shipped in 0.6.8.
final class MapRegionsBundleTests: XCTestCase {

    private var atlas: RegionAtlas!

    override func setUp() async throws {
        try await super.setUp()
        await RegionAtlas.shared.loadIfNeeded()
        atlas = RegionAtlas.shared
        try XCTSkipUnless(atlas.isLoaded, "MapRegions.json missing from the test bundle")
    }

    private static func bundleURL() throws -> URL {
        let candidates = [Bundle(for: RegionAtlas.self), Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in candidates {
            if let url = bundle.url(forResource: "MapRegions", withExtension: "json") {
                return url
            }
        }
        throw XCTSkip("MapRegions.json not resolvable from the test bundle")
    }

    func testBundleSizeStaysUnderFourMegabytes() throws {
        let url = try Self.bundleURL()
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? .max
        XCTAssertLessThanOrEqual(size, 4 * 1024 * 1024, "\(size) bytes")
    }

    /// The twenty countries the app breaks into regions — the only ones
    /// `region(containing:)` can ever attribute a trip to. Every one of them
    /// must also carry a country-level outline for world-zoom drawing.
    private static let atlasCountryCodes = [
        "RU", "GE", "AM", "AZ", "KZ", "BY", "UA", "FI", "EE", "LV",
        "LT", "MD", "PL", "MN", "TR", "KG", "UZ", "TJ", "TM", "NO",
    ]

    func testEveryAtlasCountryCarriesRings() {
        let byId = Dictionary(uniqueKeysWithValues: atlas.countries.map { ($0.id, $0) })
        for code in Self.atlasCountryCodes {
            guard let country = byId[code] else {
                XCTFail("no MapCountry entry for \(code)")
                continue
            }
            XCTAssertFalse(country.rings.isEmpty, "\(code) has no rings")
        }
    }

    /// Below twelve points a region reads as an octagon, not a border — the
    /// exact class of over-simplification that shredded Adjara's coastline.
    func testEveryRegionHasAtLeastTwelveVertices() {
        XCTAssertFalse(atlas.regions.isEmpty)
        for region in atlas.regions {
            let vertexCount = region.rings.reduce(0) { $0 + $1.count / 2 }
            XCTAssertGreaterThanOrEqual(vertexCount, 12, "\(region.id) has only \(vertexCount) vertices")
        }
    }

    /// Frozen hit vectors. Batumi and Kobuleti sit on the same coast road,
    /// and both must resolve to the same region for «до моря N км» to agree
    /// with itself. Kobuleti is the regression case: the old, coarser
    /// Adjara ring left it outside GE-AJ.
    func testFrozenHitVectors() {
        let cases: [(id: String, coordinate: CLLocationCoordinate2D)] = [
            ("RU-KDA", CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753)),
            ("GE-AJ", CLLocationCoordinate2D(latitude: 41.6168, longitude: 41.6367)),
            ("GE-AJ", CLLocationCoordinate2D(latitude: 41.82, longitude: 41.78)),
            ("GE-TB", CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271)),
        ]
        for testCase in cases {
            XCTAssertEqual(
                atlas.region(containing: testCase.coordinate)?.id, testCase.id,
                "\(testCase.coordinate.latitude), \(testCase.coordinate.longitude)")
        }
    }
}
