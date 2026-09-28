import XCTest

/// Кадры дома: строка в листе вида карты, пустой экран дома, поставленный
/// дом с кругом зоны и включённая зона.
final class HomeSheetShotTests: XCTestCase {

    func testHomeFlow() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "dark",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()

        let atlas = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(atlas.waitForExistence(timeout: 30))
        atlas.tap()
        sleep(4)

        app.buttons["atlas_appearance"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["atlas_appearance_sheet"].firstMatch
            .waitForExistence(timeout: 10))
        usleep(1_200_000)
        snap(app, "h1_appearance_with_home_row")

        // Строка дома ведёт на свой экран: лист вида карты закрывается, дом
        // открывается следующим. Ожидание — по появлению экрана дома.
        app.buttons["atlas_home_row"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["home_sheet"].firstMatch.waitForExistence(timeout: 15),
                      "экран дома не открылся из листа вида карты")
        usleep(1_500_000)
        snap(app, "h2_home_empty")

        // Дом ставится пальцем по карте — другого входа нет.
        let map = app.otherElements["home_map"].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        map.tap()
        usleep(1_500_000)
        XCTAssertTrue(app.buttons["home_radius_500"].firstMatch.waitForExistence(timeout: 10),
                      "после тапа по карте дом не появился: нет выбора радиуса")
        snap(app, "h3_home_placed")

        app.buttons["home_radius_1000"].firstMatch.tap()
        usleep(1_200_000)
        snap(app, "h4_radius_1000")

        let zone = app.switches["home_zone_toggle"].firstMatch
        if zone.waitForExistence(timeout: 5) {
            zone.tap()
            usleep(1_200_000)
            snap(app, "h5_zone_on")
        }

        // Главное обещание тумблера «Показывать на карте»: метка появляется
        // на самом «Атласе», а не только в листе настройки.
        // Закрываем лист: кнопка ×, а если её не видно — свайпом вниз. Оба
        // пути одинаково законны для человека, и тест не должен падать
        // из-за того, каким из них он пошёл.
        let close = app.descendants(matching: .any)
            .matching(identifier: "atlas_controls_close").firstMatch
        if close.waitForExistence(timeout: 5), close.isHittable {
            close.tap()
        } else {
            app.otherElements["home_sheet"].firstMatch.swipeDown(velocity: .fast)
        }
        usleep(2_500_000)
        XCTAssertTrue(app.otherElements["home_pin"].firstMatch.waitForExistence(timeout: 15)
                      || app.images["home_pin"].firstMatch.exists,
                      "метки дома нет на «Атласе» — состояние не доехало до карты")
        snap(app, "h6_pin_on_atlas")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
