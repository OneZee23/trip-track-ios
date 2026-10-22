import XCTest

/// Somebody else's level opens «Уровни» (0.9.1, owner 22 Oct 2026: «хочу
/// чтобы была возможность на уровень другого пользователя нажимать и
/// получать информацию об этом»).
///
/// Offline fixture: level 21 with 26 400 XP. The screen is the one «Я» opens,
/// with the owner's name under the title and the bar to level 22.
final class PublicLevelsFlowTests: XCTestCase {
    func testTheLevelOpensLevelsWithTheOwnersXP() throws {
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

        let level = app.buttons["public_lvl_pill"].firstMatch
        XCTAssertTrue(level.waitForExistence(timeout: 10), "The level on a profile is a button")
        attach(app, "public_level_pill")
        level.tap()

        let screen = app.descendants(matching: .any)["levels_screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Test Traveller"].firstMatch.exists, "The subtitle names whose level it is")
        let bar = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "XP", "28")).firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "The bar counts the owner's XP to level 22")
        attach(app, "public_levels_screen")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
