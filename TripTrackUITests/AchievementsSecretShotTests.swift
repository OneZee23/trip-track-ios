import XCTest

/// Именной значок секрета на полке «Достижения» (0.7.0, волна 5).
///
/// Значок `secret_komsomolsky` скрытый: до находки человек видит плитку «?», а
/// не название района. Проверить это можно только отсюда — `isHidden` в
/// каталоге ничего не говорит о том, ЧТО нарисовано, а нарисованное решает
/// `AchievementsCatalogue.state(for:)` вместе с записанным в `UserDefaults`
/// списком открытых.
///
/// Два кадра, два запуска: сид разводит их аргументами (`-seed-secret-badge`
/// открывает значок), потому что один запуск не может показать плитку и до, и
/// после. Порядок методов — алфавитный, `hidden` раньше `unlocked`, и это
/// важно: открытый значок живёт в `UserDefaults` и переживает перезапуск, так
/// что кадр «до» снимается на СВЕЖЕЙ установке (`simctl uninstall` перед
/// прогоном). Если порядок всё-таки сломается, тест не соврёт кадром — он
/// упадёт на проверке имени.
final class AchievementsSecretShotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += [
            "-hasCompletedOnboarding", "<true/>", "-seed-map-demo", "-seed-discoveries",
        ]
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// «Я» → «Достижения» → фильтр «Секретные».
    private func openSecretShelf() {
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 12), "вкладка «Я» на месте")
        profile.tap()
        usleep(2_000_000)

        let all = app.buttons.matching(identifier: "profile_achievements_all").firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 8), "строка «Достижения» в профиле")
        all.tap()
        XCTAssertTrue(app.otherElements["achievements_screen"].waitForExistence(timeout: 8),
                      "экран достижений открылся")
        usleep(1_500_000)

        let secret = app.buttons.matching(identifier: "achievements_filter_secret").firstMatch
        XCTAssertTrue(secret.waitForExistence(timeout: 5), "сегмент «Секретные»")
        secret.tap()
        usleep(1_200_000)
    }

    /// Имя значка на полке — «Знак Комсомольского» / «The Komsomolsky Mark».
    /// Ищется по обоим написаниям: язык приложения берётся от симулятора.
    private func namedCell() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS[c] 'Komsomol' OR label CONTAINS[c] 'Комсомольск'"))
            .firstMatch
    }

    func test_achievements_secret_hidden() {
        app.launch()
        openSecretShelf()
        snap("w070_w5_achievements_secret")

        XCTAssertGreaterThan(
            app.descendants(matching: .any).matching(identifier: "achievement_cell").count, 0,
            "полка секретных не пуста")
        XCTAssertFalse(namedCell().exists,
                       "до находки секрет стоит плиткой «?», а не своим именем")
    }

    func test_achievements_secret_unlocked() {
        app.launchArguments += ["-seed-secret-badge"]
        app.launch()
        openSecretShelf()

        XCTAssertTrue(namedCell().waitForExistence(timeout: 4),
                      "после находки плитка называет секрет по имени")
        // Полка секретных длиннее экрана, и открытая плитка стоит среди
        // одинаковых «?» — кадр без неё доказывал бы только счётчик в шапке.
        for _ in 0..<6 where !namedCell().isHittable {
            app.windows.firstMatch.swipeUp()
            usleep(600_000)
        }
        usleep(600_000)
        snap("w070_w5_achievements_secret_unlocked")
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }
}
