import XCTest
import MapKit
@testable import TripTrack

/// Штора на время зума: поднимается на щипке, на панораме — НИКОГДА.
///
/// Тест существует потому, что ошибка здесь — это экран, на котором человек
/// возит пальцем и не видит ничего, а поймать такое открытым приложением
/// нельзя: панорама и зум приходят одним и тем же колбэком.
final class MapZoomCurtainTests: XCTestCase {

    // MARK: - Порог

    func testPanNeverRaisesTheCurtain() {
        // Сдвиг камеры не меняет ширину видимого прямоугольника ВОВСЕ — именно
        // поэтому величина выбрана такой, а не по `span.latitudeDelta`,
        // который на Меркаторе растёт при движении на север.
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 1_000))
    }

    /// Границы — ровно 0.85 и 1.15, и обе снаружи.
    func testThresholdBoundaries() {
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 1_149))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 1_151))
        // Вниз порог тоже отношением: 1 / 1.15 ≈ 0.8696.
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 880))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 860))
        XCTAssertEqual(MapZoomCurtain.threshold, 0.15, accuracy: 0.0001)
    }

    func testThresholdIsSymmetricInRatio() {
        // Порог — отношение, а не разность: увеличение вдвое и уменьшение
        // вдвое обязаны считаться одинаково сильным зумом.
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 2_000))
        XCTAssertTrue(MapZoomCurtain.shouldRaise(startWidth: 2_000, currentWidth: 1_000))
    }

    func testZeroWidthIsNotAZoom() {
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startWidth: 0, currentWidth: 1_000))
        XCTAssertFalse(MapZoomCurtain.shouldRaise(startWidth: 1_000, currentWidth: 0))
    }

    // MARK: - Состояние

    func testZoomOutRaisesOnceAndLowersWhenTheCameraStops() {
        var curtain = MapZoomCurtain()
        curtain.willChange(width: 1_000)
        XCTAssertFalse(curtain.changing(width: 1_050), "дрожание руки — не зум")
        XCTAssertTrue(curtain.changing(width: 1_400))
        XCTAssertTrue(curtain.isUp)
        XCTAssertFalse(curtain.changing(width: 2_000), "поднятую штору не поднимают второй раз")

        XCTAssertNotNil(curtain.didChange(width: 2_000), "камера встала — гасить")
        XCTAssertFalse(curtain.isUp)
    }

    func testPanFromEndToEndNeverRaisesAndNeverFades() {
        var curtain = MapZoomCurtain()
        curtain.willChange(width: 1_000)
        for _ in 0..<20 { XCTAssertFalse(curtain.changing(width: 1_000)) }
        XCTAssertNil(curtain.didChange(width: 1_000), "гасить нечего — штора не поднималась")
    }

    /// Затухание, начатое прошлым жестом, не имеет права досчитаться поверх
    /// нового: человек щипнул второй раз, пока гасло первое.
    func testNewGestureCancelsThePendingFade() {
        var curtain = MapZoomCurtain()
        curtain.willChange(width: 1_000)
        _ = curtain.changing(width: 1_500)
        guard let fade = curtain.didChange(width: 1_500) else {
            return XCTFail("после зума затухание обязано начаться")
        }
        XCTAssertTrue(curtain.fadeIsCurrent(fade))

        curtain.willChange(width: 1_500)
        XCTAssertFalse(curtain.fadeIsCurrent(fade), "новый жест не отменил прошлое затухание")
        XCTAssertTrue(curtain.changing(width: 2_200), "второй щипок поднимает штору заново")
    }

    func testFadeDurationIsQuarterOfASecond() {
        // Столько же, сколько MapKit довозит свежие тайлы оверлея: короче — и
        // из-под шторы снова покажется карта Apple.
        XCTAssertEqual(MapZoomCurtain.fadeDuration, 0.25, accuracy: 0.0001)
    }
}
