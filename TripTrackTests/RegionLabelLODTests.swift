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

    // MARK: - `.far` регионы НЕ прячет (фикс-волна 5)

    /// Подпись региона существует только у ПОСЕЩЁННОГО, а посещённый на
    /// дальнем уровне залит охрой: залитое пятно без имени — вопрос без
    /// ответа. Раньше ярус гасил её здесь, и увидеть заливку с именем можно
    /// было только в узкой полосе `.mid`, которую камера проходит насквозь за
    /// один двойной тап.
    func testFarShowsAVisitedRegionThatIsLargeEnough() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 10_000, lod: .far, isCountry: false))
    }

    /// Но мелкий край на мировом зуме по-прежнему молчит — его отсекает bbox,
    /// а не ярус.
    func testFarStillHidesARegionSqueezedToNothing() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 40, lod: .far, isCountry: false))
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
