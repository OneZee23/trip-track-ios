import XCTest

/// Лист «Вид карты» — кадром.
///
/// Его высоту дважды ломала попытка мерить содержимое: внутри `ScrollView`,
/// измерение уходит вниз и не возвращается, и лист схлопывается до одной
/// шапки. Теперь высота задана числом, и проверить это можно только снимком —
/// состоянием высоту листа не спросить.
final class AtlasAppearanceSheetShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    func test_appearance_sheet_shows_all_three_styles() {
        let atlas = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 20), "нет вкладки «Атлас»")
        atlas.tap()

        let layers = app.buttons["atlas_appearance"]
        XCTAssertTrue(layers.waitForExistence(timeout: 15), "нет кнопки вида карты")
        layers.tap()
        sleep(2)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "appearance"
        shot.lifetime = .keepAlways
        add(shot)

        // Лист обязан показывать всё, ради чего его открыли: три стиля и
        // тумблер. Схлопнутый лист не покажет ни одного.
        XCTAssertTrue(app.otherElements["atlas_appearance_sheet"].waitForExistence(timeout: 5),
                      "лист не открылся\n\(app.debugDescription)")
        XCTAssertTrue(app.switches["atlas_photos_toggle"].exists,
                      "тумблера не видно — лист схлопнулся")
    }

    /// Выбранный стиль обязан доехать ДО КАРТЫ.
    ///
    /// Жмутся ВСЕ три плитки по очереди, а не одна: стиль сохраняется между
    /// запусками (`AtlasMapAppearance.saved`), и тап по уже выбранному —
    /// пустая операция. Первая редакция этого теста именно на ней и
    /// «проверяла» переключение: кадры совпадали, потому что ничего и не
    /// просили менять.
    func test_picking_a_style_changes_the_map() {
        let atlas = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 20))
        atlas.tap()
        sleep(3)

        var frames: [String: Data] = [:]
        for style in ["fog", "night", "cells"] {
            app.buttons["atlas_appearance"].tap()
            let tile = app.buttons["atlas_style_\(style)"].firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 5), "нет плитки \(style)")
            tile.tap()
            sleep(1)
            app.buttons["atlas_controls_close"].firstMatch.tap()
            sleep(3)
            let shot = XCUIScreen.main.screenshot()
            frames[style] = shot.pngRepresentation
            let a = XCTAttachment(screenshot: shot)
            a.name = "map_\(style)"; a.lifetime = .keepAlways
            add(a)
        }

        // Сравниваются только пары, различающиеся ПАЛИТРОЙ.
        //
        // «Туман» и «Клетки» здесь заведомо совпадут, и это не поломка: на
        // симуляторе Metal-вуаль в дерево `MKMapView` не садится, туман
        // рисует растровый откат, а у него клеток нет по определению
        // (см. CLAUDE.md, «Клетки»). Зонд в отрисовке это и показал — ни
        // одного кадра Metal за весь прогон. Значит клетки проверяются
        // офскрином (`FogMetalCellsTests`) и глазами на устройстве, а этот
        // тест сторожит то, что здесь проверяемо: выбор стиля доезжает до
        // карты.
        XCTAssertNotEqual(frames["fog"], frames["night"], "«Туман» и «Ночь» дали одну картинку")
        XCTAssertNotEqual(frames["night"], frames["cells"], "«Ночь» и «Клетки» дали одну картинку")
    }
}
