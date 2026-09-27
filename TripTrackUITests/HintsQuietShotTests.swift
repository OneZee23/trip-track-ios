import XCTest

/// Кадры ТИХОЙ подсказки: кольцо без строки на карте и карточка загадки,
/// которую открывает нажатие по нему.
///
/// Владелец на устройстве 17 сен: «сильно много внимания на себя берут секреты
/// и кружки вокруг них — сделать скрытнее. И они не интерактивные: нельзя
/// нажать и посмотреть подробнее». Оба ответа видны только глазами: «стало ли
/// тише» не выражается ни возвращаемым значением, ни числом пикселей, а
/// карточка — это лист поверх карты.
///
/// До городского масштаба доезжаем ДВОЙНЫМИ ТАПАМИ ПО САМОЙ ПОДСКАЗКЕ, как
/// `RiddleHintShotTests`: карта зумит к точке касания, и круг остаётся в кадре.
final class HintsQuietShotTests: XCTestCase {
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

    private func hint() -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", "border post"))
            .firstMatch
    }

    func test_quiet_hints_and_card() {
        XCTAssertTrue(app.buttons["atlas_explored_title"].waitForExistence(timeout: 12))
        usleep(2_500_000)

        for _ in 0..<4 {
            let badge = hint()
            guard badge.waitForExistence(timeout: 6) else { break }
            badge.doubleTap()
            usleep(1_500_000)
        }
        // Двойной тап попадает и в дорогу под кругом — снизу поднимается
        // карточка «16 поездок на этой дороге». Кадр про круг, а не про неё.
        let close = app.buttons.matching(identifier: "mymap_close").firstMatch
        if close.exists { close.tap() }
        usleep(2_500_000)
        snap("w070_hints_quiet_city")

        // Нажатие по значку — карточка загадки: строка, «решается проездом» и
        // расстояние. Координаты в ней нет ни в каком виде.
        let badge = hint()
        if badge.waitForExistence(timeout: 6) {
            badge.tap()
            usleep(2_000_000)
        }
        snap("w070_hints_card")
    }
}
