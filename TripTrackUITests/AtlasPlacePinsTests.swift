import XCTest

/// Свои места на карте «Атласа» (макет «Места» 0.8.1, S8).
///
/// Что булавка встала на карту и что её нажатие показывает карточку — это
/// видно только кадром и деревом доступности: `placePins` у вью-модели
/// непустой и на сломанном экране тоже (аннотации могли не доехать до карты —
/// ровно та поломка, которую 0.8.1 чинил у периода и региона).
final class AtlasPlacePinsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_atlas_shows_place_pins_and_card() {
        // Места заводит сверка на запуске; второй запуск — ради тёплого кэша
        // геокодера, иначе у булавок нет имён (см. `PlacesTabShotTests`).
        let places = app.buttons.matching(identifier: "tab_places").firstMatch
        XCTAssertTrue(places.waitForExistence(timeout: 20), "нет вкладки «Места»")
        places.tap()
        _ = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'place_card_'"))
            .firstMatch.waitForExistence(timeout: 60)

        let atlas = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 10), "нет вкладки «Атлас»")
        atlas.tap()
        sleep(5)
        snap("w081_atlas_places")

        let pins = app.otherElements.matching(identifier: "place_pin")
        XCTAssertGreaterThan(pins.count, 0,
                             "булавок мест на «Атласе» нет\n\(app.debugDescription)")

        // Нажатие по булавке обязано показать карточку — иначе она украшение.
        let pin = pins.firstMatch
        if pin.isHittable {
            pin.tap()
            let card = app.buttons["atlas_place_card"]
            XCTAssertTrue(card.waitForExistence(timeout: 5),
                          "карточка места не появилась\n\(app.debugDescription)")
            snap("w081_atlas_place_card")
        }
    }
}
