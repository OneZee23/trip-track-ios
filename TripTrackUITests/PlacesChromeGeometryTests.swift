import XCTest

/// Хром «Мест» стоит на месте во всех положениях панели.
///
/// Тот же сторож, что у «Атласа», и заведён он до того, как поломка
/// случилась: слой, выставленный в координатах экрана и не помещающийся в
/// свой контейнер, заставляет SwiftUI сдвинуть безопасную зону ВСЕГО ОКНА —
/// и уезжает весь экран, включая таб-бар. На «Атласе» это стоило волны
/// правок; здесь оно ловится числом с первого дня.
final class PlacesChromeGeometryTests: XCTestCase {
    private var app: XCUIApplication!
    /// Безопасная зона сверху на канонном симуляторе (iPhone 16).
    private let safeTop: CGFloat = 59

    private func launch(theme: String) {
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich",
            "-appLanguage", "ru", "-appThemeMode", theme,
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        let places = app.buttons["tab_places"].firstMatch
        XCTAssertTrue(places.waitForExistence(timeout: 30), "нет вкладки «Места»")
        places.tap()
        XCTAssertTrue(app.buttons["places_beta_chip"].firstMatch.waitForExistence(timeout: 30),
                      "вкладка не приехала")
        usleep(2_500_000)
    }

    private var tabBar: CGRect { app.buttons["tab_places"].firstMatch.frame }
    private var chip: CGRect {
        let c = app.buttons["places_beta_chip"].firstMatch
        return c.exists ? c.frame : .zero
    }
    private var panelTop: CGFloat {
        app.otherElements["places_panel_handle"].firstMatch.frame.minY
    }

    func testChromeHoldsAcrossEveryPanelStop() { walk(theme: "light") }
    func testChromeHoldsInDarkTheme() { walk(theme: "dark") }

    private func walk(theme: String) {
        launch(theme: theme)
        let rest = tabBar
        XCTAssertFalse(rest.isEmpty, "таб-бара нет")

        var seen: [(String, CGRect, CGRect)] = [("половина", tabBar, chip)]

        app.buttons["places_mode_list"].firstMatch.tap()
        usleep(2_000_000)
        seen.append(("список", tabBar, chip))

        app.buttons["places_mode_map"].firstMatch.tap()
        usleep(2_000_000)
        seen.append(("карта", tabBar, chip))

        let pin = app.otherElements.matching(identifier: "place_pin").firstMatch
        if pin.waitForExistence(timeout: 15), pin.isHittable {
            pin.tap()
            usleep(2_000_000)
            seen.append(("выбрана булавка", tabBar, chip))
        }

        for (name, bar, head) in seen {
            XCTAssertEqual(bar.minY, rest.minY, accuracy: 0.6, "таб-бар уехал: \(name)")
            XCTAssertFalse(head.isEmpty, "заголовок панели пропал: \(name)")
            XCTAssertGreaterThanOrEqual(head.minY, safeTop,
                                        "заголовок ушёл под статус-бар: \(name)")
        }
    }

    /// Положения панели — те самые числа, что считает `PlacesSlot`.
    func testPanelStopsMatchTheSlot() {
        launch(theme: "light")
        let h = app.windows.firstMatch.frame.height
        let tabBarTop = h - 22 - 68

        XCTAssertEqual(panelTop, tabBarTop - 374, accuracy: 1, "половина")

        app.buttons["places_mode_map"].firstMatch.tap()
        usleep(2_000_000)
        XCTAssertEqual(panelTop, tabBarTop - 100, accuracy: 1, "карта")

        app.buttons["places_mode_list"].firstMatch.tap()
        usleep(2_000_000)
        XCTAssertEqual(panelTop, safeTop + 56, accuracy: 1, "список")
    }
}
