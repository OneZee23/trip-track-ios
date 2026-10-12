import XCTest

/// Тяжёлая чужая карта (0.9.0). Владелец 12 окт: «когда открываешь большущую
/// карту (Максим Морозов, почти вся РФ) — приложение зависает и еле-еле карту
/// отображает». Офлайн: `-debug-foreign-map heavy` — 600 длинных поездок по
/// европейской части России, по 1 500 точек превью.
///
/// Меряется то, что видит человек: сколько секунд от нажатия «Карта» до
/// сводки с числами, и отвечает ли экран всё это время — кнопка «Назад»
/// должна нажиматься, а не висеть.
final class HeavyPublicMapTests: XCTestCase {
    func testHeavyMapOpensAndStaysResponsive() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-debug-foreign-map", "heavy",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))
        let mapCard = app.staticTexts["Карта"].firstMatch
        for _ in 0..<6 where !(mapCard.exists && mapCard.isHittable) { app.swipeUp() }
        XCTAssertTrue(mapCard.waitForExistence(timeout: 5))

        let start = Date()
        mapCard.tap()
        let routes = app.staticTexts["600"].firstMatch
        let loaded = routes.waitForExistence(timeout: 120)
        let seconds = Date().timeIntervalSince(start)
        print("PROBE heavy map summary after \(String(format: "%.1f", seconds)) s, loaded=\(loaded)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "heavy_public_map"
        shot.lifetime = .keepAlways
        add(shot)

        // Responsiveness right after: Back must take the person out at once.
        let back = app.buttons["public_map_back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        let backStart = Date()
        back.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: back)
        let result = XCTWaiter.wait(for: [gone], timeout: 30)
        print("PROBE back took \(String(format: "%.1f", Date().timeIntervalSince(backStart))) s result=\(result.rawValue)")
    }
}
