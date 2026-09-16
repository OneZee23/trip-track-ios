import XCTest

/// Кадры «Атласа» на четырёх масштабах — то, ради чего правилась кисть 16
/// сентября: ореол по масштабу, облака с рваным краем, границы регионов и
/// заливка посещённых.
///
/// Владелец на устройстве: «всё скудно, тонкие линии… просто тупо тёмная
/// зона, на которой тоненькие оранжевые полоски». Ни «открытое читается
/// площадью», ни «туман похож на облака», ни «видно, какие это регионы» не
/// выражаются ни возвращаемым значением, ни состоянием — проверяются они
/// кадрами.
final class AtlasLookShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-places-rich",
        ]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var win: XCUIElement { app.windows.firstMatch }

    /// Щипок по ВЕРХНЕЙ половине экрана: нижнюю треть занимает лист «Атласа»,
    /// и жест по ней двигал бы лист, а не карту.
    private func pinch(_ scale: CGFloat) {
        win.pinch(withScale: scale, velocity: scale > 1 ? 2 : -2)
        usleep(1_500_000)
    }

    /// Летит к самому наезженному региону через лист «Атласа» — так же, как
    /// это делает человек. Щипками вслепую до города не доехать.
    private func flyToBusiestRegion() {
        let summary = app.otherElements["mymap_summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        summary.tap()
        usleep(1_200_000)
        let row = app.otherElements["mymap_region_list"].buttons
            .matching(NSPredicate(format: "identifier != 'mymap_close'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6))
        row.tap()
        usleep(2_000_000)
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap() }
        usleep(1_500_000)
    }

    func test_atlas_look_shots() {
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 12))
        usleep(3_000_000)

        // Страна: камера на старте вмещает всё открытое, один щипок наружу
        // уводит её на уровень, где рисуются только границы стран.
        pinch(0.45)
        snap("w070_atlas_look_country")

        // Регион: лист «Атласа» приводит камеру РОВНО на открытое этого
        // региона. Щипками вслепую сюда не доехать — камера считает центром
        // середину экрана и на втором приближении уходит за сотню километров.
        flyToBusiestRegion()
        snap("w070_atlas_look_region")

        // Город и улица: двойной тап ПО САМОМУ коридору — он и приближает, и
        // оставляет открытое в середине кадра. Щипок вокруг середины экрана
        // этого не делает: нижнюю треть занимает лист, и «середина карты» у
        // человека выше середины экрана.
        let onTheRoad = CGVector(dx: 0.52, dy: 0.29)
        win.coordinate(withNormalizedOffset: onTheRoad).doubleTap()
        usleep(2_000_000)
        dismissCard()
        snap("w070_atlas_look_city")

        for _ in 0..<2 {
            win.coordinate(withNormalizedOffset: onTheRoad).doubleTap()
            usleep(2_000_000)
            dismissCard()
        }
        usleep(1_500_000)
        snap("w070_atlas_look_street")
    }

    /// Тап по коридору выбирает дорогу и раскрывает лист — его надо закрыть,
    /// иначе он накрывает половину кадра.
    private func dismissCard() {
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap(); usleep(1_000_000) }
    }

}
