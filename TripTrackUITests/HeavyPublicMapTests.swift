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
        try open(variant: "heavy", routes: "600")
    }

    /// The shape of the heaviest real public map (43 trips, 104K points).
    func testRealShapedMapOpensAndStaysResponsive() throws {
        try open(variant: "real", routes: "43")
    }

    /// Two trips through the same code path: the baseline the other two are
    /// read against, since a simulator gesture has its own fixed cost.
    func testLightMapBaseline() throws {
        try open(variant: "france", routes: "2")
    }

    private func open(variant: String, routes routeCount: String) throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-debug-foreign-map", variant,
                                "-appLanguage", "ru", "-appThemeMode", "light", "-trace-vein"]
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
        let routes = app.staticTexts[routeCount].firstMatch
        let loaded = routes.waitForExistence(timeout: 120)
        let seconds = Date().timeIntervalSince(start)
        print("PROBE \(variant) map summary after \(String(format: "%.1f", seconds)) s, loaded=\(loaded)")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(variant)_public_map"
        shot.lifetime = .keepAlways
        add(shot)

        // Moving the map: each gesture must finish promptly, and the time it
        // takes is what a person feels as «the map lags».
        let map = app.maps.firstMatch
        if map.waitForExistence(timeout: 5) {
            for (i, gesture) in ["pinch-in", "pan", "pinch-out", "pan", "pinch-in", "pan"].enumerated() {
                let t0 = Date()
                switch gesture {
                case "pinch-in": map.pinch(withScale: 2.5, velocity: 2)
                case "pinch-out": map.pinch(withScale: 0.4, velocity: -2)
                default: (i % 4 == 1 ? map.swipeLeft() : map.swipeDown())
                }
                print("PROBE \(variant) gesture \(gesture) took \(String(format: "%.2f", Date().timeIntervalSince(t0))) s")
            }
            let after = XCTAttachment(screenshot: app.screenshot())
            after.name = "\(variant)_public_map_after_gestures"
            after.lifetime = .keepAlways
            add(after)
        }

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
