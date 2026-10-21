import XCTest

/// Кадры экрана статистики и «Я» рядом (0.9.1) — «до» редизайна статистики.
/// Владелец 21 окт 2026: «экран статистики… как будто пережиток прошлого,
/// сильно криво и просто выглядит»; эталон — «Я». Сид `-seed-map-demo`,
/// обе темы, экран за экраном при прокрутке. Ничего не утверждает, только
/// снимает: сравнивать кадры будет человек.
final class StatsScreenShotTests: XCTestCase {

    private func snap(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name; att.lifetime = .keepAlways; add(att)
    }

    private func walk(theme: String) {
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
                                "-appLanguage", "ru", "-appThemeMode", theme]
        app.launch()
        defer { app.terminate() }

        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        let strip = app.buttons["profile_stats_strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        sleep(2)
        snap("me_\(theme)_1")
        app.swipeUp(); usleep(800_000)
        snap("me_\(theme)_2")
        app.swipeDown(); app.swipeDown(); usleep(800_000)

        strip.tap()
        XCTAssertTrue(app.otherElements["stats_screen"].firstMatch.waitForExistence(timeout: 10)
                      || app.descendants(matching: .any)["stats_screen"].firstMatch.waitForExistence(timeout: 5))
        sleep(2)
        for i in 1...4 {
            snap("stats_\(theme)_\(i)")
            app.swipeUp(); usleep(800_000)
        }
    }

    func testStatsAndMeLight() { walk(theme: "light") }
    func testStatsAndMeDark() { walk(theme: "dark") }
}
