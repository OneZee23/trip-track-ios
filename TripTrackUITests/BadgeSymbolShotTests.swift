import XCTest

/// Как значки-символы выглядят на своих местах — только кадром.
///
/// Набор заменён на символы без оправы, а контейнер теперь рисует приложение:
/// плитка в полосе профиля, голый символ на карточке и у закреплённого.
/// Сошлись ли заливка плитки и символ в обеих темах — вопрос к глазу, а не к
/// состоянию.
final class BadgeSymbolShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_badges_on_profile_and_shelf() {
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "нет вкладки «Я»")
        me.tap()
        sleep(3)
        app.swipeUp()
        sleep(1)
        snap("profile_strip")

        // Полка достижений целиком.
        let all = app.buttons.matching(NSPredicate(
            format: "identifier CONTAINS 'achievements'")).firstMatch
        if all.waitForExistence(timeout: 5) {
            all.tap()
            sleep(3)
            snap("achievements_shelf")
        }
    }
}
