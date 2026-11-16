import XCTest

@MainActor
final class FilmingModeShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    func testAtlasAndPlacesWithFilmingModeOnAndOff() {
        for filming in [false, true] {
            app = XCUIApplication()
            app.launchArguments = ["-hasCompletedOnboarding", "<true/>", "-ui-testing",
                                   "-appLanguage", "ru", "-AppleLanguages", "(ru)",
                                   "-appThemeMode", "light", "-seed-map-demo",
                                   "-seed-places-demo", "-seed-places-rich",
                                   "-seed-hidden-parts", "-seed-filming-mode"]
            if filming { app.launchArguments.append("-force-filming-mode") }
            app.launch()

            let atlasTab = app.buttons["tab_maps"].firstMatch
            XCTAssertTrue(atlasTab.waitForExistence(timeout: 30))
            atlasTab.tap()
            XCTAssertTrue(app.buttons["atlas_explored_title"].waitForExistence(timeout: 30))
            usleep(1_200_000)
            capture("filming-atlas-\(filming ? "on" : "off")")

            let placesTab = app.buttons["tab_places"].firstMatch
            XCTAssertTrue(placesTab.waitForExistence(timeout: 15))
            placesTab.tap()
            let placesReady = app.buttons["places_mode_list"].waitForExistence(timeout: 30)
            XCTAssertTrue(placesReady, "Places screen did not load\n\(app.debugDescription)")
            usleep(1_200_000)
            capture("filming-places-\(filming ? "on" : "off")")
            app.terminate()
        }
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
