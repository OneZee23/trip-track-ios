import XCTest

/// Кадры «Атласа» на трёх масштабах и во время зума — то, ради чего правилась
/// вуаль 16 сентября.
///
/// Владелец на устройстве: круг загадки растёт вместе с отдалением, анимация
/// зума «пьяная», а по краям видны подгружаемые квадратики. Ни одно из трёх не
/// выражается ни возвращаемым значением, ни состоянием: проверяется это
/// кадрами. Отдельный тест `test_atlas_zoom_out_sequence` нарочно ничего не
/// снимает сам — под ним снаружи идёт `simctl io screenshot` каждые сто
/// миллисекунд, и «квадратики» ищутся в этой последовательности.
final class AtlasPolishShotTests: XCTestCase {
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
    /// это делает человек. Щипками вслепую до города не доехать: камера
    /// считает центром середину экрана и на втором приближении уходит от
    /// открытого за сотню километров.
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

    func test_atlas_polish_shots() {
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 12))
        usleep(3_000_000)

        // Страна: круги подсказок на этом масштабе меньше 60 pt в диаметре,
        // значков быть не должно вовсе — только выгравированные кольца.
        pinch(0.4)
        usleep(1_500_000)
        snap("w070_atlas_polish_country")

        // Регион/город — через лист, а не щипком.
        flyToBusiestRegion()
        snap("w070_atlas_polish_city")

        // Улица: два двойных тапа по середине открытого.
        for _ in 0..<2 {
            win.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).doubleTap()
            usleep(1_500_000)
        }
        let closeRoad = app.buttons.matching(identifier: "mymap_close").firstMatch
        if closeRoad.exists { closeRoad.tap() }
        usleep(2_000_000)
        snap("w070_atlas_polish_street")

        // Подсказка: возвращаемся к обзору (за краем экрана `doubleTap` по
        // аннотации падает — подвезти её прокруткой карта не умеет) и
        // доезжаем двойными тапами по самой подсказке.
        pinch(0.25)
        pinch(0.4)
        usleep(1_500_000)
        for _ in 0..<5 {
            let hint = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "border post"))
                .firstMatch
            guard hint.waitForExistence(timeout: 6), hint.isHittable else { break }
            hint.doubleTap()
            usleep(1_500_000)
        }
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap() }
        usleep(2_000_000)
        snap("w070_atlas_polish_hint")
    }

    /// Медленное отдаление: четыре щипка подряд с паузами. Кадры снимает
    /// внешний цикл — здесь только движение камеры.
    func test_atlas_zoom_out_sequence() {
        XCTAssertTrue(app.otherElements["mymap_summary"].waitForExistence(timeout: 12))
        usleep(3_000_000)
        pinch(4)
        usleep(1_000_000)
        for _ in 0..<4 {
            win.pinch(withScale: 0.35, velocity: -3)
            usleep(1_200_000)
        }
        usleep(2_000_000)
    }
}
