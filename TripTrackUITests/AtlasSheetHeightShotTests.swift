import XCTest

/// Высота листов «Атласа» — только кадром.
///
/// `contentSizedSheet` меряет СОДЕРЖИМОЕ, а `ScrollView` внутри забирает всю
/// предложенную высоту: лист, у которого скролл первым ребёнком, от такой
/// мерки становится полноэкранным вместо короткого. Состоянием этого не
/// спросить — только снимком.
final class AtlasSheetHeightShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_atlas_sheets_are_no_taller_than_their_content() {
        let atlas = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 20), "нет вкладки «Атлас»")
        atlas.tap()

        let period = app.buttons["atlas_period"]
        XCTAssertTrue(period.waitForExistence(timeout: 15), "нет кнопки периода")
        period.tap()
        sleep(2)
        snap("sheet_period")

        // Свой период — тот самый календарь из «Я».
        let custom = app.buttons["atlas_period_custom"].firstMatch
        if custom.waitForExistence(timeout: 3) {
            custom.tap()
        } else {
            app.staticTexts["Свой период"].firstMatch.tap()
        }
        sleep(2)
        snap("sheet_custom")

        // Закрыть и открыть вид карты.
        app.swipeDown()
        sleep(1)
        let layers = app.buttons["atlas_layers"]
        if layers.waitForExistence(timeout: 5) {
            layers.tap()
            sleep(2)
            snap("sheet_appearance")
        }
    }
}
