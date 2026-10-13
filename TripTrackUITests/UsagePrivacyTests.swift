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
        // iOS 26 exposes the label and switch as one accessibility frame;
        // tap the actual control at its trailing edge, then wait for the
        // accessibility value to catch up with the SwiftUI state update.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1'"), object: toggle)], timeout: 3), .completed)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '0'"), object: toggle)], timeout: 3), .completed)
        app.terminate()
    }
}
