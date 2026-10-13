import XCTest

/// Подсостояние «Регион» в нижнем слоте (спека, состояние 16).
///
/// Сменило `AtlasRegionCardTests` и `AtlasRegionExpandedTests`: прежней
/// панели региона больше нет, а с ней ушли и «потяни вверх», и заголовок
/// отдельным слоем поверх статус-бара. Вопрос, на который отвечает этот
/// сторож, один — МОЖЕТ ЛИ ЧЕЛОВЕК ВЫЙТИ. Именно он 27 сентября и не мог:
/// «нажимаю на стрелочку влево… и ничего не происходит».
final class AtlasRegionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
            "-appLanguage", "ru", "-appThemeMode", "light",
            "-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"
        ]
        app.launch()
        let maps = app.buttons["tab_maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 30))
        maps.tap()
        XCTAssertTrue(app.buttons["atlas_explored_title"].firstMatch.waitForExistence(timeout: 30))
        usleep(1_500_000)
    }

    private var summaryTitle: XCUIElement { app.buttons["atlas_explored_title"].firstMatch }

    private func openList() {
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
            .press(forDuration: 0.05,
                   thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        usleep(1_500_000)
    }

    private func openFirstRegion() {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'atlas_region_'"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "строки региона нет")
        row.tap()
        usleep(2_500_000)
    }

    /// Шапка региона живёт В ШТОРКЕ и ниже статус-бара — не поверх часов.
    func testTheRegionHeaderLivesInsideTheSheet() {
        openList()
        openFirstRegion()

        let back = app.buttons["atlas_substate_back"].firstMatch
        let close = app.buttons["atlas_substate_close"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "нет кнопки «назад»")
        XCTAssertTrue(close.exists, "нет кнопки «закрыть»")
        XCTAssertTrue(back.isHittable && close.isHittable, "выходы обязаны нажиматься")

        let sheetTop = app.buttons["atlas_sheet_handle"].firstMatch.frame.minY
        XCTAssertGreaterThan(back.frame.minY, sheetTop,
                             "шапка обязана быть ВНУТРИ шторки, а не поверх экрана")
        XCTAssertGreaterThanOrEqual(back.frame.height, 44, "цель пальца не меньше 44")
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
    }

    /// «Назад» возвращает ТУДА, ОТКУДА ПРИШЛИ: из списка — в список.
    func testBackFromTheListReturnsToTheList() {
        openList()
        openFirstRegion()
        app.buttons["atlas_substate_back"].firstMatch.tap()
        usleep(2_000_000)

        XCTAssertFalse(app.buttons["atlas_substate_back"].firstMatch.exists, "регион не закрылся")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'atlas_region_'"))
            .firstMatch.waitForExistence(timeout: 5), "список не вернулся")
    }

    /// × закрывает подсостояние до сводки — это другой ответ, чем у «назад»,
    /// и ради этого их и двое.
    func testCloseReturnsToTheSummary() {
        openList()
        openFirstRegion()
        let h = app.windows.firstMatch.frame.height
        app.buttons["atlas_substate_close"].firstMatch.tap()
        usleep(2_000_000)

        XCTAssertFalse(app.buttons["atlas_substate_back"].firstMatch.exists, "регион не закрылся")
        XCTAssertEqual(app.buttons["atlas_sheet_handle"].firstMatch.frame.minY,
                       h - 22 - 68 - 220, accuracy: 1, "шторка не вернулась в сводку")
        XCTAssertTrue(summaryTitle.exists)
    }

    /// Утянутое вниз подсостояние закрывается — то же, чего человек ждёт от
    /// любой шторки.
    func testPullingTheRegionDownCloses() {
        openList()
        openFirstRegion()
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56))
            .press(forDuration: 0.05,
                   thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)))
        usleep(2_000_000)
        XCTAssertFalse(app.buttons["atlas_substate_back"].firstMatch.exists,
                       "жест вниз не закрыл регион")
        XCTAssertTrue(summaryTitle.exists)
    }

    /// Поездки региона достаются жестом вверх: на своей высоте они уходят под
    /// таб-бар, и это единственная причина, по которой подсостоянию разрешено
    /// подниматься до списка.
    func testTheRegionOpensItsTripsWhenPulledUp() {
        openList()
        openFirstRegion()
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.58))
            .press(forDuration: 0.05,
                   thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)))
        usleep(2_000_000)
        XCTAssertTrue(app.buttons["atlas_region_trip"].firstMatch.waitForExistence(timeout: 10),
                      "поездок региона не видно")
        XCTAssertTrue(app.buttons["atlas_substate_back"].firstMatch.isHittable,
                      "выход обязан остаться на месте и в списке")
    }
}
