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

/// Подпись региона уступает синей точке «я здесь».
///
/// Столкновениями MapKit это не решается: `MKUserLocationView` в общий счёт
/// приоритетов не входит, и подпись ложилась прямо под кружком — увидел
/// владелец на устройстве 22 сентября. Правило чистое, потому что проверить
/// его на живой карте нечем: точка приезжает от GPS.
final class RegionLabelUserDotTests: XCTestCase {
    private let label = CGRect(x: 100, y: 100, width: 120, height: 30)

    func testALabelUnderTheDotYields() {
        // Центр точки внутри самой подписи — тот самый кадр со скриншота.
        XCTAssertTrue(RegionLabelLOD.yieldsToUserDot(
            labelFrame: label, userDotCentre: CGPoint(x: 160, y: 115)))
    }

    func testALabelTouchingTheDotHaloYields() {
        // Точка рядом, но её запас (22 pt) накрывает край подписи.
        XCTAssertTrue(RegionLabelLOD.yieldsToUserDot(
            labelFrame: label, userDotCentre: CGPoint(x: 232, y: 115)))
    }

    func testALabelClearOfTheDotStays() {
        // Дальше запаса — подпись остаётся: прятать её «на всякий случай»
        // значило бы терять имя края там, где оно ничему не мешает.
        XCTAssertFalse(RegionLabelLOD.yieldsToUserDot(
            labelFrame: label, userDotCentre: CGPoint(x: 260, y: 115)))
    }

    func testWithoutALocationNothingYields() {
        XCTAssertFalse(RegionLabelLOD.yieldsToUserDot(labelFrame: label, userDotCentre: nil))
    }

    func testAnUnmeasuredLabelDecidesNothing() {
        // Рамки ещё нет (вью не разложена) — прятать нечего и не за что.
        XCTAssertFalse(RegionLabelLOD.yieldsToUserDot(
            labelFrame: .zero, userDotCentre: CGPoint(x: 160, y: 115)))
    }
}
