import XCTest
@testable import TripTrack

/// `RegionLabelLOD.level`: видна ли подпись региона или страны на этом
/// масштабе. Чистая функция — проверяется без карты, порогами и краевыми
/// значениями.
final class RegionLabelLODTests: XCTestCase {

    // MARK: - Регион: порог 140 pt

    func testRegionVisibleAtThreshold() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 140, lod: .mid, isCountry: false))
    }

    func testRegionHiddenJustBelowThreshold() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 139.9, lod: .mid, isCountry: false))
    }

    func testRegionVisibleOnFineWhenLargeEnough() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 500, lod: .fine, isCountry: false))
    }

    // MARK: - `.far` прячет регионы

    func testFarHidesRegionsRegardlessOfSize() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 10_000, lod: .far, isCountry: false))
    }

    // MARK: - Страна: порог 90 pt, только на `.far`

    func testCountryVisibleAtThresholdOnFar() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 90, lod: .far, isCountry: true))
    }

    func testCountryHiddenJustBelowThreshold() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 89.9, lod: .far, isCountry: true))
    }

    func testCountryHiddenOffFarEvenWhenLarge() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 10_000, lod: .mid, isCountry: true))
    }

    // MARK: - `.fine` прячет всё

    func testFineHidesCountriesAndSmallRegions() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 10, lod: .fine, isCountry: false))
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 10, lod: .fine, isCountry: true))
    }
}
