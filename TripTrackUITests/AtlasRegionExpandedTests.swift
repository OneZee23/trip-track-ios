import XCTest

/// Развёрнутая карточка региона и её список поездок.
///
/// Владелец 26 сентября: «когда тяну увеличить эту панель, она раскрывается
/// во что-то… криво выглядит», и отдельно — «нажимаю 68 все поездки, а если у
/// меня их будет больше 1000? Это же пипец интерфейсу». Снимок — потому что
/// «криво» не выражается ни значением, ни состоянием.
final class AtlasRegionExpandedTests: XCTestCase {
    func testExpandedRegionShowsItsTrips() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()

        let maps = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 25))
        maps.tap()
        let region = app.buttons["atlas_region_RU-KDA"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 25))
        region.tap()
        usleep(3_000_000)
        snap("atlas_region_collapsed")

        // Плитка «N поездок» — вход в список; она же и раскрывает карточку.
        let card = app.otherElements["mymap_region_card"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "карточка региона не открылась")
        let expand = app.buttons["mymap_expand_trips"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 10), "подсказка «потяни вверх» обязана быть кнопкой")
        expand.tap()
        usleep(3_000_000)
        snap("atlas_region_expanded")
        XCTAssertTrue(app.buttons["mymap_open_trip"].firstMatch.exists
                      || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Краснодар'")).count > 0,
                      "в раскрытой карточке обязан быть список поездок")
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
