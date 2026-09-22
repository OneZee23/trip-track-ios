import XCTest
@testable import TripTrack

/// Выключатель Metal-тумана и режим «только вектор» у растровой вуали.
///
/// `isEnabled == true` — продакшен 0.8.0; тест на само значение стоит
/// нарочно: смена флага — решение владельца, а не побочный эффект задачи, и
/// она обязана ронять тест, который потом удаляют вместе с решением.
final class FogMetalAvailabilityTests: XCTestCase {

    override func tearDown() {
        FogMetalAvailability.isEnabledOverride = nil
        super.tearDown()
    }

    func testShippedBuildDrawsFogWithMetal() {
        XCTAssertTrue(FogMetalAvailability.isEnabled)
        XCTAssertTrue(FogMetalAvailability.isActive,
                      "без переопределения «активно» это и есть прод-значение")
    }

    func testOverrideTurnsTheFlagOff() {
        FogMetalAvailability.isEnabledOverride = false
        XCTAssertFalse(FogMetalAvailability.isActive)
        // И обратно: шов не однонаправленный, иначе тест, которому Metal
        // нужен, не смог бы его вернуть.
        FogMetalAvailability.isEnabledOverride = true
        XCTAssertTrue(FogMetalAvailability.isActive)
    }

    /// Вуаль в режиме «только вектор» не заказывает ни одного растра: мглу
    /// рисует `FogMetalVeil`, и платить за картинку, которую никто не увидит,
    /// незачем.
    ///
    /// Индекс путей при этом строится по-прежнему, и это НЕ недосмотр:
    /// бакеты `MapPathIndex` — единственный источник жилки сети
    /// (`FogVeilVein.strokes` принимает `MapPathChunks`), а жилка на
    /// «Атласе» остаётся вуали. Утверждать здесь «индекс не строится»
    /// значило бы сторожить картинку, отличную от эталона 0.8.0.
    @MainActor
    func testVectorOnlyVeilOrdersNoRaster() {
        let veil = FogVeilView(margin: FogVeilView.atlasMargin)
        veil.vectorOnly = true
        veil.setLayer(.empty)

        XCTAssertEqual(veil.renderOrders, 0, "слой сам по себе растра не заказывает")
        XCTAssertEqual(veil.veinStrokeCount, 0, "растра нет — и жилке пока некуда лечь")
    }
}
