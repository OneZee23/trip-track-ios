import XCTest

/// The legal links under Settings take a finger (0.8.9). They carried
/// `.frame(minHeight: 44)` and still measured 13 pt: a frame on a label does
/// not widen what the button hit-tests. Now `tapTarget()`.
final class SettingsTapTargetsTests: XCTestCase {
    func testFooterLinksAreFingerSized() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()
        let tab = app.buttons["tab_profile"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 40))
        tab.tap()
        let gear = app.buttons["profile_gear"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        let policy = app.buttons["settings_privacy_policy"].firstMatch
        XCTAssertTrue(policy.waitForExistence(timeout: 5))
        for _ in 0..<4 where !policy.isHittable { app.swipeUp() }
        for id in ["settings_privacy_policy", "settings_terms", "settings_osm_attribution"] {
            let link = app.buttons[id].firstMatch
            XCTAssertTrue(link.exists, id)
            XCTAssertGreaterThanOrEqual(link.frame.height, 40, "\(id) is \(link.frame.height) pt tall")
        }
    }
}
