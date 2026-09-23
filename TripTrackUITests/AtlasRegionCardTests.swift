import XCTest

/// Карточка региона владеет низом экрана целиком.
///
/// Правило 0.7.0: у выбранной карточки таб-бар спрятан — «a selected card owns
/// the bottom of the screen, and the bar sitting on top of it clipped the
/// progress row clean off» (`MyMapView.hideAppTabBar`). Владелец прислал кадр
/// 23 сентября, где пилюля стоит прямо на карточке края: либо правило
/// перестало работать, либо кадр снят посреди перехода. Отличить одно от
/// другого можно только настоящим касанием, отсюда UI-тест.
///
/// Гонять ТОЛЬКО этот класс: полный UI-таргет виснет (CLAUDE.md).
final class AtlasRegionCardTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTheRegionCardHidesTheTabBar() {
        let tab = app.buttons.matching(identifier: "tab_maps").firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "вкладка «Атлас» на месте")
        tab.tap()

        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 20), "свёрнутая карточка поднята")
        XCTAssertTrue(tab.isHittable, "пока карточка свёрнута, бар на месте")
        summary.tap()

        let row = app.otherElements["mymap_region_list"].buttons
            .matching(NSPredicate(format: "identifier != 'mymap_close'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "строка региона в журнале")
        row.tap()

        // Переход карточки — 0.28 с; секунда с запасом покрывает и его, и
        // уезжающий бар.
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "карточка региона открыта")
        sleep(2)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "region-card"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertFalse(tab.isHittable,
                       "у открытой карточки региона таб-бар обязан быть убран")

        // Второй вход в ту же карточку — палец по карте, а не строка журнала.
        // Владелец открывает её именно так, и путь там другой: `selectRegion`
        // вместо строки списка.
        close.tap()
        sleep(1)
        // Целимся в подпись посещённого региона: она стоит РОВНО над своим
        // регионом, и тап по ней — это тап по карте в нужном месте. Слепой
        // тап по середине экрана попадает в пустоту, и проверка молчала бы,
        // ничего не проверив.
        let label = app.otherElements
            .matching(NSPredicate(format: "label CONTAINS[c] 'KRASNODAR KRAI'")).firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 10), "подпись региона на карте")
        label.tap()
        sleep(2)

        let second = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        second.name = "region-card-from-map-tap"
        second.lifetime = .keepAlways
        add(second)

        XCTAssertTrue(app.buttons.matching(identifier: "mymap_close").firstMatch.exists,
                      "тап по карте открыл карточку региона")
        XCTAssertFalse(tab.isHittable,
                       "карточка, открытая тапом по карте, тоже убирает бар")
    }
}
