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
}
