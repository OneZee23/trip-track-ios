import XCTest
@testable import TripTrack

/// `RegionLabelLOD.level`: видна ли подпись региона на этом масштабе. Чистая
/// функция — проверяется без карты, порогом и краевыми значениями.
///
/// Страны (свой более низкий порог, только на `.far`) были здесь до 17
/// сентября — их подписи и контуры на «Атласе» убраны вместе с границами.
final class RegionLabelLODTests: XCTestCase {

    // MARK: - Регион: порог 140 pt

    func testRegionVisibleAtThreshold() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 140))
    }

    func testRegionHiddenJustBelowThreshold() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 139.9))
    }

    func testRegionVisibleWhenLargeEnough() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 500))
    }

    /// Подпись региона существует только у ПОСЕЩЁННОГО, поэтому она не гаснет
    /// ни на одном уровне детали — bbox решает сам, без яруса.
    func testVeryLargeBboxStaysVisible() {
        XCTAssertTrue(RegionLabelLOD.level(bboxMinSidePt: 10_000))
    }

    /// А мелкий край на мировом зуме по-прежнему молчит.
    func testTinyBboxStaysHidden() {
        XCTAssertFalse(RegionLabelLOD.level(bboxMinSidePt: 10))
    }
}
