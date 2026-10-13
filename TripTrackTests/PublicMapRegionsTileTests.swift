import XCTest
@testable import TripTrack

/// «0 регионов» на чужой карте (12 окт 2026): ноль при непустых маршрутах — не
/// число, а страна, которую атлас регионов не делит. С 13 окт атлас делит весь
/// мир, и офлайн-фикстура (Франция) до этого пути больше не доходит, поэтому
/// правило держит этот тест, а не снимок.
final class PublicMapRegionsTileTests: XCTestCase {
    func testZeroRegionsBesideRoutesIsHidden() {
        XCTAssertTrue(PublicMapView.hidesRegions(regions: 0, trips: 2))
    }

    func testCountedRegionsAreShown() {
        XCTAssertFalse(PublicMapView.hidesRegions(regions: 21, trips: 2))
    }

    func testAnEmptyMapHidesNothing() {
        XCTAssertFalse(PublicMapView.hidesRegions(regions: 0, trips: 0))
    }
}
