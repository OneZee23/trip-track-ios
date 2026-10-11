import XCTest

/// Small text links on «Я» take a finger (0.8.9): «13 из 35 ›» opens the
/// achievements and «Октябрь ⌄» opens the month — each was a 16 pt row of
/// text. Checked by tapping above the drawn text, inside the 44 pt target.
final class ProfileTapTargetsTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
    }

    override func tearDownWithError() throws { app = nil }

    private func tapAbove(_ element: XCUIElement) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 40, "\(element.identifier) target")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    func testAchievementsLinkTakesATapAboveItsText() {
        let toggle = app.buttons["profile_sections_toggle"].firstMatch
        if toggle.waitForExistence(timeout: 5) { toggle.tap() }
        let link = app.buttons["profile_achievements_all"].firstMatch
        for _ in 0..<4 where !(link.exists && link.isHittable) { app.swipeUp() }
        XCTAssertTrue(link.isHittable)
        tapAbove(link)
        XCTAssertTrue(app.descendants(matching: .any)["achievements_screen"].firstMatch.waitForExistence(timeout: 5))
    }

    func testMonthLinkTakesATapAboveItsText() {
        let month = app.buttons["profile_calendar_month"].firstMatch
        for _ in 0..<6 where !(month.exists && month.isHittable) { app.swipeUp() }
        XCTAssertTrue(month.isHittable)
        tapAbove(month)
        XCTAssertTrue(app.buttons["profile_calendar_clear"].firstMatch.waitForExistence(timeout: 3)
                      || !app.buttons["profile_calendar_month"].firstMatch.exists,
                      "The month view must open")
    }
}
