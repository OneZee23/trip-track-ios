import XCTest

/// Кадр третьего стиля карты — «Клетки» (0.8.2, макет A7).
///
/// Снимком, а не состоянием: «открытое стало квадратами» не выражается ни
/// возвращаемым значением, ни флагом. Пиксельные сторожа
/// (`FogMetalCellsTests`) держат геометрию на офскрине, здесь — что стиль
/// доезжает до живой карты через лист настроек.
final class AtlasCellsShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-rich",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_atlas_cells_style() {
        let atlas = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 20), "нет вкладки «Атлас»")
        atlas.tap()
        sleep(5)

        // Приблизиться: на масштабе страны клетка мельче порога и стиль
        // молча выключается — снимать там нечего.
        let win = app.windows.firstMatch
        for _ in 0..<3 { win.pinch(withScale: 3, velocity: 3); usleep(900_000) }
        snap("w082_atlas_fog_before")

        let controls = app.buttons.matching(identifier: "atlas_appearance").firstMatch
        guard controls.waitForExistence(timeout: 5), controls.isHittable else {
            XCTFail("нет кнопки вида карты\n\(app.debugDescription)")
            return
        }
        controls.tap()
        sleep(1)
        snap("w082_controls_three_styles")

        let cells = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Клетки' OR label CONTAINS[c] 'Cells'")).firstMatch
        guard cells.waitForExistence(timeout: 3) else {
            XCTFail("нет плитки «Клетки»\n\(app.debugDescription)")
            return
        }
        cells.tap()
        sleep(2)
        // Диагностика: встал ли выбор в самом листе. Отличает «тап не попал»
        // от «выбор встал, но не доехал до карты».
        snap("w082_controls_after_tap")
        // Закрыть лист, чтобы карта была видна целиком.
        app.buttons.matching(identifier: "atlas_controls_close").firstMatch.tap()
        sleep(2)
        snap("w082_atlas_cells_after")
    }
}
