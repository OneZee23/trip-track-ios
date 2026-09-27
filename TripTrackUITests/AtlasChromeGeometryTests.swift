import XCTest

/// Хром «Атласа» стоит на месте во всех состояниях вкладки.
///
/// Это сторож на поломку 27 сентября, и поломка была не косметической.
/// Слой шторки и слой кнопок карты жили в координатах ЭКРАНА: первый
/// выносился наружу `.ignoresSafeArea()`, второй отодвигался от низа
/// отступом в семьсот точек. Оба перестали помещаться в свой контейнер, как
/// только шторку раскрывали, — и SwiftUI отвечал тем, что менял безопасную
/// зону ВСЕГО ОКНА. Замеры: заголовок вкладки уезжал с 59 pt на 19.7 (то есть
/// под часы), таб-бар — с 768 на 773.7, потом на 751. На экране владельца это
/// выглядело как «шапка наслаивается с остальными элементами телефона сверху,
/// хрен пойми куда нажимать».
///
/// Числом, а не кадром: сдвиг в сорок точек виден глазом, а сдвиг в пять —
/// нет, и он-то и означает, что безопасная зона снова поехала. Спека §4
/// требует буквально: «таб-бар стоит на месте во всех состояниях вкладки и
/// никогда не анимируется сам по себе».
final class AtlasChromeGeometryTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(theme: String) {
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-seed-places-demo", "-seed-places-rich",
            "-appLanguage", "ru", "-appThemeMode", theme,
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        let maps = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 30), "нет вкладки «Атлас»")
        maps.tap()
        XCTAssertTrue(app.buttons["atlas_explored_title"].firstMatch.waitForExistence(timeout: 30),
                      "сводка не приехала")
        usleep(1_500_000)
    }

    // MARK: Опорные точки

    private var tabBar: CGRect { app.buttons["tab_maps"].firstMatch.frame }
    private var header: CGRect { app.buttons["atlas_beta_chip"].firstMatch.frame }
    /// Верх шторки меряется по ручке: она стоит ровно на верхнем краю
    /// (`AtlasSheet.handle`) и есть в любом положении и в подсостоянии.
    private var sheetTop: CGFloat { app.buttons["atlas_sheet_handle"].firstMatch.frame.minY }

    private func drag(fromY: CGFloat, toY: CGFloat) {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
            .press(forDuration: 0.05,
                   thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY)))
        usleep(1_500_000)
    }

    private func tapStrip() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        usleep(1_500_000)
    }

    // MARK: Сторожа

    func testChromeNeverMovesAcrossAtlasStates() { walkEveryState(theme: "light") }

    /// Тёмная тема — те же размеры (спека, состояния 20 и 21). Отдельным
    /// прогоном, а не параметром: тему читает запуск приложения.
    func testChromeNeverMovesInDarkTheme() { walkEveryState(theme: "dark") }

    private func walkEveryState(theme: String) {
        launch(theme: theme)

        let restTabBar = tabBar
        let restHeader = header
        XCTAssertFalse(restTabBar.isEmpty, "таб-бара нет")
        XCTAssertFalse(restHeader.isEmpty, "заголовка вкладки нет")

        var seen: [(String, CGRect, CGRect)] = [("сводка", restTabBar, restHeader)]

        drag(fromY: 0.72, toY: 0.2)
        seen.append(("список", tabBar, header))

        tapStrip()
        seen.append(("сводка после тапа по полоске карты", tabBar, header))

        // Модальная шторка «Вид карты»: она НАКРЫВАЕТ таб-бар, но не двигает
        // его — спека §4 разрешает первое и запрещает второе.
        app.buttons["atlas_appearance"].firstMatch.tap()
        usleep(1_500_000)
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        usleep(1_500_000)
        seen.append(("после шторки «Вид карты»", tabBar, header))

        // Выбранное место: слот занимает карточка, шторка уходит в подсказку.
        let pin = app.otherElements.matching(identifier: "place_pin").firstMatch
        if pin.waitForExistence(timeout: 20), pin.isHittable {
            pin.tap()
            usleep(2_000_000)
            let close = app.buttons["atlas_place_close"].firstMatch
            if close.waitForExistence(timeout: 5) {
                seen.append(("карточка места", tabBar, header))
                close.tap()
                usleep(1_500_000)
            }
        }

        // Регион и его список поездок.
        drag(fromY: 0.72, toY: 0.2)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'atlas_region_'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "строки региона нет")
        row.tap()
        usleep(2_500_000)
        seen.append(("регион", tabBar, header))

        let back = app.buttons["atlas_substate_back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "в подсостоянии нет кнопки «назад»")
        XCTAssertTrue(back.isHittable, "кнопка «назад» не нажимается")
        XCTAssertGreaterThan(back.frame.minY, restHeader.minY - 1,
                             "кнопка «назад» обязана быть НИЖЕ статус-бара, а не под часами")

        drag(fromY: 0.58, toY: 0.18)
        seen.append(("поездки региона", tabBar, header))

        app.buttons["atlas_substate_back"].firstMatch.tap()
        usleep(2_000_000)
        seen.append(("после «назад»", tabBar, header))

        for (name, bar, head) in seen {
            XCTAssertEqual(bar.minY, restTabBar.minY, accuracy: 0.6, "таб-бар уехал: \(name)")
            XCTAssertEqual(head.minY, restHeader.minY, accuracy: 0.6, "заголовок уехал: \(name)")
        }
    }

    /// Положения шторки — те самые числа, что считает `AtlasSlot`.
    func testSheetStopsWhereTheSlotSaysItShould() {
        launch(theme: "light")
        let h = app.windows.firstMatch.frame.height
        let tabBarTop = h - 22 - 68
        let safeTop = header.minY - 4

        XCTAssertEqual(sheetTop, tabBarTop - 166, accuracy: 1, "сводка")
        drag(fromY: 0.72, toY: 0.2)
        XCTAssertEqual(sheetTop, safeTop + 56, accuracy: 1, "список")

        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'atlas_region_'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        usleep(2_500_000)
        XCTAssertEqual(sheetTop, tabBarTop - 298, accuracy: 1, "подсостояние региона")
    }

    /// Полоска карты над списком — это «свернуть», а НЕ «выбрать регион».
    ///
    /// 27 сентября она не значила ничего, и тап уходил прямо в карту, которая
    /// честно выбирала край под пальцем: «нажимаю на пустую область сверху,
    /// думая, что закрою модалку, а мне открывается другая».
    func testTappingTheMapStripCollapsesTheListInsteadOfOpeningARegion() {
        launch(theme: "light")
        drag(fromY: 0.72, toY: 0.2)
        let h = app.windows.firstMatch.frame.height
        tapStrip()
        XCTAssertFalse(app.buttons["atlas_substate_back"].firstMatch.exists,
                       "тап по полоске карты открыл регион вместо того, чтобы свернуть список")
        XCTAssertEqual(sheetTop, h - 22 - 68 - 166, accuracy: 1, "список не свернулся")
    }
}
