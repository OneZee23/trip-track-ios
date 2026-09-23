import XCTest

/// Карточка региона ложится ВЫШЕ таб-бара, а не под него.
///
/// Канон 0.7.0 прятал бар под выбранной карточкой. На симуляторе он и правда
/// уезжал, а на устройстве владельца оставался — два кадра подряд, 23
/// сентября, с пилюлей поверх карточки: «сливается всё, некрасиво». Правило,
/// которое работает через раз, заменено на одно состояние: бар под карточкой
/// ОСТАЁТСЯ, а карточка считает свою высоту вместе с местом под него
/// (`MyMapSheet.detailPanel`). Проверяется это настоящим касанием — хит-тест
/// и раскладку иначе не спросить.
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

    func testTheRegionCardSitsAboveTheTabBar() {
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

        XCTAssertTrue(tab.isHittable, "бар под карточкой остаётся на месте")
        let card = app.otherElements["mymap_region_card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "карточка региона на экране")
        // Содержимое карточки кончается ВЫШЕ пилюли: «сливается» — это когда
        // между последней строкой и баром семь точек.
        XCTAssertLessThan(tab.frame.minY, card.frame.maxY,
                          "бар стоит поверх нижнего края карточки — так и задумано")

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
        XCTAssertTrue(tab.isHittable, "и здесь бар на месте, карточка над ним")
    }
}
