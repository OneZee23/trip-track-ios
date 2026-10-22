import XCTest

/// Somebody else's whole collection opens from their profile (0.9.1, owner
/// 22 Oct 2026: «хочу посмотреть список всех ачивок другого юзера»).
///
/// Offline fixture: the profile's `recentBadges` holds five ids and
/// `/users/:id/badges` ten, one of them an earned secret. The card must count
/// the ten, and the screen behind it must be the «Достижения» screen with the
/// owner's name under the title.
final class PublicAchievementsFlowTests: XCTestCase {
    func testTheCardOpensTheWholeCollection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))

        let all = app.buttons["public_achievements_all"].firstMatch
        for _ in 0..<8 where !(all.exists && all.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(all.waitForExistence(timeout: 5), "The card links to the whole collection")
        XCTAssertTrue(all.label.hasPrefix("10 из "), "The card counts the whole list, not the preview: \(all.label)")
        attach(app, "public_achievements_card")

        all.tap()
        let screen = app.descendants(matching: .any)["achievements_screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Traveller"].firstMatch.exists, "The subtitle names whose collection it is")
        let opened = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "10 из ")).firstMatch
        XCTAssertTrue(opened.waitForExistence(timeout: 5), "The hero counts the same ten")
        attach(app, "public_achievements_screen")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
