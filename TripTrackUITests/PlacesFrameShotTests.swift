import XCTest

/// Кадры каркаса «Мест»: половина, список, карта, выбранная булавка.
final class PlacesFrameShotTests: XCTestCase {
    func testPlacesFrame() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        let places = app.buttons["tab_places"].firstMatch
        XCTAssertTrue(places.waitForExistence(timeout: 30))
        places.tap()
        _ = app.buttons["places_beta_chip"].firstMatch.waitForExistence(timeout: 30)
        sleep(4)
        snap("p1_half")

        app.buttons["places_mode_list"].firstMatch.tap()
        usleep(2_000_000)
        snap("p2_list")

        app.buttons["places_mode_map"].firstMatch.tap()
        usleep(2_000_000)
        snap("p3_map")

        let pin = app.otherElements.matching(identifier: "place_pin").firstMatch
        if pin.waitForExistence(timeout: 15), pin.isHittable {
            pin.tap()
            usleep(2_000_000)
            snap("p4_selected")
        }

        print("DIAG handle = \(app.otherElements["places_panel_handle"].firstMatch.frame)")
        print("DIAG tabbar = \(app.buttons["tab_places"].firstMatch.frame)")
        print("DIAG chip   = \(app.buttons["places_beta_chip"].firstMatch.frame)")
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
