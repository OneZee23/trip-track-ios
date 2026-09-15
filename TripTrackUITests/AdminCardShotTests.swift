import XCTest

/// Снимок карточки «Админ» в листе настроек (0.7.0).
///
/// Своим ходом её не увидеть: карточка показывается по `is_admin` из ответа
/// сервера, а на симуляторе нет ни сессии, ни сервера. Запуск с
/// `-debug-admin` рисует её так, как её увидит владелец — флаг живёт в
/// `NotificationSwitches` под `#if DEBUG` и в релиз не попадает.
final class AdminCardShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-admin"]
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test_admin_card() {
        // Восстановленная запись уводит приложение с таб-бара — та же
        // нормализация, что у остальных туров.
        let recovery = app.buttons.matching(identifier: "recovery_continue").firstMatch
        if recovery.waitForExistence(timeout: 3), recovery.isHittable {
            recovery.tap(); sleep(2)
        }
        let me = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(me.waitForExistence(timeout: 20), "нет вкладки «Я»")
        me.tap(); sleep(2)

        let gear = app.buttons.matching(identifier: "profile_gear").firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "нет шестерёнки")
        gear.tap(); sleep(2)

        XCTAssertTrue(
            app.switches.matching(identifier: "settings_admin_new_accounts").firstMatch
                .waitForExistence(timeout: 5)
                || app.descendants(matching: .any)
                    .matching(identifier: "settings_admin_new_accounts").firstMatch.exists,
            "карточки «Админ» нет в листе настроек"
        )
        snap("w070_admin_sheet")
    }
}
