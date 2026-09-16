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

    /// Below twelve points a LARGE region reads as an octagon, not a border —
    /// the exact class of over-simplification that shredded Adjara's
    /// coastline. That is a guard against RDP throwing away too much detail,
    /// not a rule about the source data: a handful of small city-level
    /// subjects (Nakhchivan city AZ-NX, Mingecevir AZ-MI, Valmiera LV-VMR)
    /// carry fewer than twelve points in Natural Earth's OWN geometry —
    /// confirmed single `Polygon` rows, nothing lost to multipart merging —
    /// and are never simplified at all (`simplify_rings` passes rings of
    /// ≤24 raw points straight through), so there is nothing to guard
    /// against there. Every region still needs at least four points to be a
    /// polygon at all; only a region with real room for RDP to have gone
    /// wrong is held to twelve.
    ///
    /// The span cutoff is 0.25°, not the 0.2° first floated: Nakhchivan city
    /// (AZ-NX) measures 0.2284° — a real administrative subject, not a
    /// rounding error — and a 0.2° line would have caught it anyway despite
    /// being exactly the genuine-sparse-data case this relaxation exists
    /// for. 0.25° clears it with room, while every region actually shredded
    /// by RDP (spans in the 1–4° range, e.g. RU-KDA) is nowhere near either
    /// number.
    func testEveryRegionHasEnoughVertices() {
        XCTAssertFalse(atlas.regions.isEmpty)
        for region in atlas.regions {
            let vertexCount = region.rings.reduce(0) { $0 + $1.count / 2 }
            XCTAssertGreaterThanOrEqual(vertexCount, 4, "\(region.id) has only \(vertexCount) vertices")
            let latSpan = region.bounds.maxLat - region.bounds.minLat
            let lonSpan = region.bounds.maxLon - region.bounds.minLon
            let span = (latSpan * latSpan + lonSpan * lonSpan).squareRoot()
            if span >= 0.25 {
                XCTAssertGreaterThanOrEqual(vertexCount, 12,
                    "\(region.id) spans \(span)° but has only \(vertexCount) vertices")
            }
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

    /// A duplicate `iso_3166_2` in a future Natural Earth update, or a bad
    /// `ISO_FIXES` entry, could reintroduce two rows sharing one `id` — the
    /// exact bug the 0.6.8 merge fix in `Tools/build_map_regions.py` already
    /// closed on the Python side. `regionIndexById` is a plain dictionary
    /// assignment, so nothing on the Swift side notices a repeat unless this
    /// asserts it.
    func testRegionIdsAreUnique() {
        let ids = atlas.regions.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate region id shipped in the bundle")
    }

    /// Review round 1: Russia's country-level outline dropped Kaliningrad —
    /// its ring ranked 14th by span, two past the old `max_rings=12` cutoff,
    /// so at world zoom the exclave read as unclaimed space between Poland
    /// and Lithuania. `country_geometry()` now force-keeps any ring covering
    /// one of the country's OWN region centroids, independent of rank.
    func testCountryOutlinesCoverTheirOwnExclaveRegions() {
        let cases: [(code: String, coordinate: CLLocationCoordinate2D)] = [
            ("RU", CLLocationCoordinate2D(latitude: 54.71, longitude: 20.51)),   // Kaliningrad
            ("AZ", CLLocationCoordinate2D(latitude: 39.21, longitude: 45.41)),   // Nakhchivan
        ]
        let byId = Dictionary(uniqueKeysWithValues: atlas.countries.map { ($0.id, $0) })
        for testCase in cases {
            guard let country = byId[testCase.code] else {
                XCTFail("no MapCountry entry for \(testCase.code)")
                continue
            }
            XCTAssertTrue(
                RegionAtlas.contains(
                    lat: testCase.coordinate.latitude, lon: testCase.coordinate.longitude,
                    rings: country.rings),
                "\(testCase.code) outline does not cover \(testCase.coordinate)")
        }
    }

    /// A synthetic duplicate, independent of whatever the shipped bundle
    /// happens to contain today: `RegionAtlas.parse(data:)` keeps the FIRST
    /// row on a repeated id and drops the rest, rather than the dictionary
    /// silently letting the last one win.
    func testParseKeepsFirstRegionOnDuplicateId() throws {
        let json = """
        {"v":1,"regions":[
          {"id":"XX-DUP","cc":"XX","ru":"Первый","en":"First",
           "c":[10.0,20.0],"b":[9.0,19.0,11.0,21.0],
           "r":[[9.0,19.0,9.0,21.0,11.0,21.0,11.0,19.0]]},
          {"id":"XX-DUP","cc":"XX","ru":"Второй","en":"Second",
           "c":[30.0,40.0],"b":[29.0,39.0,31.0,41.0],
           "r":[[29.0,39.0,29.0,41.0,31.0,41.0,31.0,39.0]]}
        ],"countries":[],"cities":[]}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let parsed = try XCTUnwrap(RegionAtlas.parse(data: data))
        XCTAssertEqual(parsed.regions.count, 1)
        XCTAssertEqual(parsed.regions.first?.nameRu, "Первый")
        XCTAssertEqual(parsed.regionIndexById, ["XX-DUP": 0])
    }

    /// A tiny, seeded (reproducible) linear-congruential generator — the
    /// stdlib has no seedable `RandomNumberGenerator`, and a fuzz test that
    /// can't be reproduced on failure is not much of a regression guard.
    private struct SeededGenerator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    /// A second, independently-written ray-caster (plain array subscripting,
    /// no `withUnsafeBufferPointer`) — the same algorithm `RegionAtlas
    /// .contains` used before its 0.7.0 speed-up, kept apart from it on
    /// purpose so this test can't pass by sharing a bug.
    private static func referenceContains(lat: Double, lon: Double, rings: [[Double]]) -> Bool {
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

    /// Behavioural equivalence for the `withUnsafeBufferPointer` rewrite:
    /// 2 000 seeded random points across five real regions, plus every
    /// actual ring vertex (the on-edge case a fuzz pass over a bounding box
    /// would only hit by luck), compared against an independent reference
    /// implementation. It's a hot path — one lookup per sampled track point
    /// across the whole library — so a silent divergence here would be wrong
    /// answers at scale, not a crash.
    func testContainsMatchesReferenceRayCasting() {
        let regionIds = ["RU-KDA", "GE-AJ", "GE-TB", "RU-ROS", "RU-STA"]
        var generator = SeededGenerator(seed: 42)
        var checked = 0

        for id in regionIds {
            guard let region = atlas.region(id: id) else {
                XCTFail("missing region \(id)")
                continue
            }
            let bounds = region.bounds

            // On-vertex: every real vertex of the region's own rings.
            for ring in region.rings {
                let count = ring.count / 2
                for i in 0..<count {
                    let lat = ring[2 * i], lon = ring[2 * i + 1]
                    XCTAssertEqual(
                        RegionAtlas.contains(lat: lat, lon: lon, rings: region.rings),
                        Self.referenceContains(lat: lat, lon: lon, rings: region.rings),
                        "\(id) vertex (\(lat), \(lon))")
                    checked += 1
                }
            }

            // Random: padded bbox so some points fall just outside the ring too.
            let latPad = max(0.01, (bounds.maxLat - bounds.minLat) * 0.1)
            let lonPad = max(0.01, (bounds.maxLon - bounds.minLon) * 0.1)
            for _ in 0..<400 {
                let lat = Double.random(
                    in: (bounds.minLat - latPad)...(bounds.maxLat + latPad), using: &generator)
                let lon = Double.random(
                    in: (bounds.minLon - lonPad)...(bounds.maxLon + lonPad), using: &generator)
                XCTAssertEqual(
                    RegionAtlas.contains(lat: lat, lon: lon, rings: region.rings),
                    Self.referenceContains(lat: lat, lon: lon, rings: region.rings),
                    "\(id) (\(lat), \(lon))")
                checked += 1
            }
        }

        XCTAssertGreaterThanOrEqual(checked, 2_000)
    }
}
