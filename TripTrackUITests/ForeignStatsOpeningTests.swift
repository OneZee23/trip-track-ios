import XCTest

/// Somebody else's Stats while their trips are still loading (0.9.1). Owner
/// 22 Oct 2026: the loading screen often showed a narrow beige column with
/// the car on a white page. On the iOS 26 push the scroll view hugged the
/// loading car's width, and the page colour only covered the scroll view.
///
/// `-debug-slow-foreign-trips` holds the trips for four seconds, so the
/// loading state stays on screen; a row under the car must be the page colour
/// edge to edge, not white.
final class ForeignStatsOpeningTests: XCTestCase {
    func testLoadingStatsFillTheWidth() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-debug-foreign-map", "real",
                                "-debug-slow-foreign-trips",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))

        let stats = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Статистика")).firstMatch
        for _ in 0..<6 where !(stats.exists && stats.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(stats.waitForExistence(timeout: 5))
        stats.tap()

        let screen = app.descendants(matching: .any)["stats_screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10))
        // Within the four seconds the trips are held: the push is over, the
        // car is still on screen.
        usleep(600_000)

        let screenshot = app.screenshot()
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "foreign_stats_loading"
        shot.lifetime = .keepAlways
        add(shot)

        let window = app.windows.firstMatch.frame
        let white = Self.whiteShare(screenshot, y: window.height * 0.45, windowWidth: window.width)
        XCTAssertLessThan(white, 0.1, "The loading page must be the page colour edge to edge (white share \(white))")
    }

    /// Share of pure-white pixels across one row; the light page is #F8F6F2.
    private static func whiteShare(_ screenshot: XCUIScreenshot, y: CGFloat, windowWidth: CGFloat) -> Double {
        guard let image = screenshot.image.cgImage else { return 1 }
        let scale = CGFloat(image.width) / windowWidth
        guard let row = image.cropping(to: CGRect(x: 0, y: (y * scale).rounded(), width: CGFloat(image.width), height: 1)),
              let data = row.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return 1 }
        let step = row.bitsPerPixel / 8
        var white = 0
        for x in 0..<row.width {
            let p = bytes + x * step
            if min(p[0], p[1], p[2]) >= 252 { white += 1 }
        }
        return Double(white) / Double(row.width)
    }
}
