import XCTest

final class UsagePrivacyTests: XCTestCase {
    func testConsentCanBeEnabledAndRevokedWithoutSigningIn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-selectedTabV2", "profile"]
        app.launch()
        let profile = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 15))
        profile.tap()
        let gear = app.buttons["profile_gear"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 10))
        gear.tap()
        let privacy = app.buttons["settings_privacy"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 5))
        privacy.tap()
        let toggle = app.switches["settings_usage_analytics"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "0")
        let before = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        before.name = "usage-consent-off"
        before.lifetime = .keepAlways
        add(before)
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.terminate()
    }
}
