import XCTest

@MainActor
final class HiddenPartsSurfaceShotTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app?.terminate() }

    func testQuestionLightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, flags: ["-open-hidden-question"])
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "hidden_edges_question").firstMatch.waitForExistence(timeout: 30))
            XCTAssertTrue(app.buttons["hidden_question_save"].exists)
            capture("hidden-question-\(theme)")
            app.terminate()
        }
    }

    func testOnboardingHiddenEdgesPageLightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, flags: ["-ui-test-onboarding", "-onboardingStartPage", "4"])
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "onboarding_hidden_edges_page").firstMatch.waitForExistence(timeout: 30))
            capture("hidden-onboarding-\(theme)")
            app.terminate()
        }
    }

    func testPrivacySettingsLightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, flags: [])
            XCTAssertTrue(app.buttons["tab_profile"].waitForExistence(timeout: 30))
            app.buttons["tab_profile"].tap()
            XCTAssertTrue(app.buttons["profile_gear"].waitForExistence(timeout: 30))
            app.buttons["profile_gear"].tap()
            XCTAssertTrue(app.buttons["settings_privacy"].waitForExistence(timeout: 15))
            app.buttons["settings_privacy"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "privacy_screen").firstMatch.waitForExistence(timeout: 30))
            XCTAssertTrue(app.buttons["privacy_home_row"].exists)
            capture("hidden-privacy-\(theme)")
            app.terminate()
        }
    }

    func testOwnTripMapStyleALightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, flags: ["-seed-hidden-parts", "-open-trip-map"])
            XCTAssertTrue(app.buttons["detail_map_expand"].waitForExistence(timeout: 45))
            capture("hidden-own-map-hero-\(theme)")
            app.buttons["detail_map_expand"].tap()
            XCTAssertTrue(app.buttons["fullscreen_map_close"].waitForExistence(timeout: 15))
            capture("hidden-own-map-fullscreen-\(theme)")
            app.terminate()
        }
    }

    func testPublishSheetWithHintLightAndDark() {
        for theme in ["light", "dark"] {
            launch(theme: theme, flags: ["-seed-hidden-parts", "-open-publish-sheet", "-debug-publish-home-hint"])
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "publish_trip_sheet").firstMatch.waitForExistence(timeout: 45))
            XCTAssertTrue(app.buttons["publish_hidden_row"].exists)
            XCTAssertTrue(app.buttons["publish_quick_hide"].exists)
            capture("hidden-publish-\(theme)")
            app.terminate()
        }
    }

    private func launch(theme: String, flags: [String]) {
        app = XCUIApplication()
        let onboarding = flags.contains("-ui-test-onboarding")
        app.launchArguments = ["-ui-testing", "-appLanguage", "ru", "-AppleLanguages", "(ru)",
                               "-appThemeMode", theme]
        if !onboarding {
            app.launchArguments += ["-hasCompletedOnboarding", "<true/>"]
        }
        app.launchArguments += flags
        app.launch()
    }

    private func capture(_ name: String) {
        usleep(700_000)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
