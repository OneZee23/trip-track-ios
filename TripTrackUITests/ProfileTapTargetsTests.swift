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

    /// The search card is 48 pt; the field inside it is a 20 pt line. A tap on
    /// the magnifier — left of the field — must focus it too.
    func testSearchCardFocusesTheFieldFromItsEdge() {
        let field = app.textFields["profile_history_search"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        // Small, slow drags: a full swipeUp flings the field past the screen.
        for _ in 0..<10 where !field.isHittable || field.frame.minY > window.frame.height - 200 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(field.isHittable)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            .withOffset(CGVector(dx: -22, dy: 0)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3),
                      "A tap on the magnifier must bring up the keyboard")
    }
}
