import XCTest
import MapKit
@testable import TripTrack

/// Штора на время зума: поднимается на щипке, на панораме и на повороте —
/// НИКОГДА.
///
/// Тест существует потому, что ошибка здесь — это экран, на котором человек
/// возит пальцем и не видит ничего, а поймать такое открытым приложением
/// нельзя: панорама, зум и поворот приходят одним и тем же колбэком.
final class MapZoomCurtainTests: XCTestCase {

    // MARK: - Порог

    func testPanNeverRaisesTheCurtain() {
        // Сдвиг камеры не меняет её высоту над центром ВОВСЕ — именно поэтому
        // величина выбрана такой, а не по `span.latitudeDelta`, который на
        // Меркаторе растёт при движении на север.
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 1_000))
    }

    /// Границы — ровно 0.85 и 1.15, и обе снаружи.
    func testThresholdBoundaries() {
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 1_149))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 1_151))
        // Вниз порог тоже отношением: 1 / 1.15 ≈ 0.8696.
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 880))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 860))
        XCTAssertEqual(MapZoomCurtain.threshold, 0.15, accuracy: 0.0001)
    }

    func testThresholdIsSymmetricInRatio() {
        // Порог — отношение, а не разность: увеличение вдвое и уменьшение
        // вдвое обязаны считаться одинаково сильным зумом.
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 2_000))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startDistance: 2_000, currentDistance: 1_000))
    }

    func testZeroDistanceIsNotAZoom() {
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startDistance: 0, currentDistance: 1_000))
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startDistance: 1_000, currentDistance: 0))
    }

    // MARK: - Поворот

    /// Главный тест этого файла. На экране записи в режиме «по курсу» карту
    /// крутит сама система, и мерили мы когда-то `visibleMapRect.size.width` —
    /// коробку вокруг видимой области, которая на телефоне 9:19.5 при повороте
    /// на 90° меняется примерно вдвое. Каждый поворот на перекрёстке гасил
    /// карту, на которую человек смотрит из-за руля.
    func testPureRotationNeverRaisesTheCurtain() {
        let centre = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
        var curtain = MapZoomCurtain()
        let start = MKMapCamera(
            lookingAtCenter: centre, fromDistance: 1_200, pitch: 0, heading: 0)
        curtain.willChange(distance: start.centerCoordinateDistance)

        // Поворот идёт градусами, а не скачком: колбэк приходит на каждый кадр.
        for heading in stride(from: 0.0, through: 90.0, by: 5.0) {
            let camera = MKMapCamera(
                lookingAtCenter: centre, fromDistance: 1_200, pitch: 0, heading: heading)
            XCTAssertFalse(
                curtain.changing(distance: camera.centerCoordinateDistance),
                "поворот на \(heading)° поднял штору — карта записи гаснет на каждом перекрёстке")
        }
        XCTAssertFalse(curtain.isUp)
    }

    /// И обратная половина: та же камера, но щипок — штора обязана встать.
    /// Иначе «не поднимается на повороте» чинилось бы порогом в бесконечность.
    func testZoomAtTheSameHeadingStillRaises() {
        let centre = CLLocationCoordinate2D(latitude: 45.035, longitude: 38.975)
        var curtain = MapZoomCurtain()
        curtain.willChange(distance: MKMapCamera(
            lookingAtCenter: centre, fromDistance: 1_200, pitch: 0, heading: 90
        ).centerCoordinateDistance)
        let zoomed = MKMapCamera(
            lookingAtCenter: centre, fromDistance: 1_200 * 1.16, pitch: 0, heading: 90)
        XCTAssertTrue(curtain.changing(distance: zoomed.centerCoordinateDistance))
    }

    /// Второй рубеж: в режиме «по курсу» камерой командует система, и штора
    /// там не поднимается вовсе — цена ошибки не лишний кадр тумана, а тёмный
    /// прямоугольник вместо карты у водителя.
    func testHeadingFollowSuppressesTheCurtainEntirely() {
        XCTAssertTrue(MapZoomCurtain.suppresses(trackingMode: .followWithHeading))
        XCTAssertFalse(MapZoomCurtain.suppresses(trackingMode: .follow))
        XCTAssertFalse(MapZoomCurtain.suppresses(trackingMode: .none))
    }

    // MARK: - Состояние

    func testZoomOutRaisesOnceAndLowersWhenTheCameraStops() {
        var curtain = MapZoomCurtain()
        curtain.willChange(distance: 1_000)
        XCTAssertFalse(curtain.changing(distance: 1_050), "дрожание руки — не зум")
        XCTAssertTrue(curtain.changing(distance: 1_400))
        XCTAssertTrue(curtain.isUp)
        XCTAssertFalse(curtain.changing(distance: 2_000), "поднятую штору не поднимают второй раз")

        XCTAssertTrue(curtain.didChange(distance: 2_000), "камера встала — гасить")
        XCTAssertFalse(curtain.isUp)
    }

    func testPanFromEndToEndNeverRaisesAndNeverFades() {
        var curtain = MapZoomCurtain()
        curtain.willChange(distance: 1_000)
        for _ in 0..<20 { XCTAssertFalse(curtain.changing(distance: 1_000)) }
        XCTAssertFalse(curtain.didChange(distance: 1_000), "гасить нечего — штора не поднималась")
    }

    /// Второй щипок, пришедший поверх ещё не догасшей шторы, поднимает её
    /// заново — отменяет затухание при этом сама вью (`removeAllAnimations`),
    /// поэтому поколения жеста у правила больше нет.
    func testSecondGestureRaisesAgain() {
        var curtain = MapZoomCurtain()
        curtain.willChange(distance: 1_000)
        _ = curtain.changing(distance: 1_500)
        XCTAssertTrue(curtain.didChange(distance: 1_500))

        curtain.willChange(distance: 1_500)
        XCTAssertTrue(curtain.changing(distance: 2_200), "второй щипок поднимает штору заново")
    }

    func testFadeDurationIsQuarterOfASecond() {
        // Столько же, сколько MapKit довозит свежие тайлы оверлея: короче — и
        // из-под шторы снова покажется карта Apple.
        XCTAssertEqual(MapZoomCurtain.fadeDuration, 0.25, accuracy: 0.0001)
    }
}
