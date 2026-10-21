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
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        // Slow drags, not swipeUp: see the month test below.
        for _ in 0..<12 where !link.isHittable
            || link.frame.minY < 140 || link.frame.maxY > window.frame.height - 160 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let step: CGFloat = link.frame.minY < 140 ? 160 : -160
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: step)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(link.isHittable)
        tapAbove(link)
        XCTAssertTrue(app.descendants(matching: .any)["achievements_screen"].firstMatch.waitForExistence(timeout: 5))
    }

    func testMonthLinkTakesATapAboveItsText() {
        let month = app.buttons["profile_calendar_month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 8))
        let window = app.windows.firstMatch
        // Small, slow drags, as for the search card below. A full swipeUp
        // flings past the target, and the hittable check runs mid-fling: the
        // page kept coasting after it, the button ended under the status bar,
        // and the edge tap landed on the status bar — iOS scrolls to top
        // (12 Oct 2026, seen once the status-bar backdrop on «Я» stopped
        // drawing the button over the clock).
        for _ in 0..<12 where !month.isHittable
            || month.frame.minY < 140 || month.frame.maxY > window.frame.height - 160 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let step: CGFloat = month.frame.minY < 140 ? 160 : -160
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: step)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
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

    /// VoiceOver reads what the eye reads. Asset paths and SF Symbol names
    /// («Badges/early_tester», «photo.on.rectangle», «Ящик входящих заполнен»)
    /// were spoken on «Я» until 0.8.9.
    func testNoAssetOrSymbolNamesReachVoiceOver() {
        let toggle = app.buttons["profile_sections_toggle"].firstMatch
        if toggle.waitForExistence(timeout: 5) { toggle.tap() }
        sleep(1)
        let tree = app.debugDescription
        for leak in ["Badges/", "photo.on.rectangle", "text.alignleft", "Ящик Входящих"] {
            XCTAssertFalse(tree.contains(leak), "VoiceOver would read «\(leak)»")
        }
    }
}
