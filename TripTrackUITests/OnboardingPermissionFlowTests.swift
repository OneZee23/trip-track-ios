import XCTest

/// Exercises the real iOS permission sheets, including refusal and Allow Once.
/// Run on an isolated simulator with the API pointed at loopback.
@MainActor
final class OnboardingPermissionFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        app.launchArguments = [
            "-ui-test-onboarding", "-onboardingStartPage", "2",
            "-appLanguage", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testDenialAndAlreadyDeniedRerunBothReachTheApp() {
        assertSingleContinue("location")
        app.swipeLeft()
        XCTAssertTrue(button("location").isHittable, "Swiping must not bypass the permission explanation")
        capture("location-explanation")
        button("location").tap()
        systemButton(["Don’t Allow", "Don't Allow"]).tap()
        finishBackgroundAndNotifications()

        // iOS does not repeat a denied location alert. Continue must still work.
        app.terminate()
        app.launch()
        assertSingleContinue("location")
        button("location").tap()
        finishBackgroundAndNotifications()
    }

    func testAllowOnceDoesNotHangOnTheSuppressedAlwaysRequest() {
        assertSingleContinue("location")
        button("location").tap()
        systemButton(["Allow Once"]).tap()
        finishBackgroundAndNotifications()
    }

    func testKeepingWhileUsingDoesNotHangOnUnchangedAuthorization() {
        assertSingleContinue("location")
        button("location").tap()
        systemButton(["Allow While Using App", "Allow While Using the App"]).tap()
        assertSingleContinue("background")
        capture("background-explanation")
        button("background").tap()
        systemButton(["Keep Only While Using", "Keep While Using"]).tap()
        finishNotifications()
    }

    private func finishBackgroundAndNotifications() {
        assertSingleContinue("background")
        button("background").tap()
        finishNotifications()
    }

    private func finishNotifications() {
        // Motion & Fitness is unavailable in Simulator; coordinator unit tests
        // cover its granted/denied callbacks and ordering on physical devices.
        assertSingleContinue("notifications")
        capture("notifications-explanation")
        button("notifications").tap()
        let deny = springboard.buttons.matching(NSPredicate(
            format: "label IN %@", ["Don’t Allow", "Don't Allow"])).firstMatch
        if deny.waitForExistence(timeout: 3) { deny.tap() }
        XCTAssertTrue(app.buttons["tab_home"].waitForExistence(timeout: 15),
                      "Refusing permissions must still finish onboarding")
    }

    private func assertSingleContinue(_ step: String) {
        let next = button(step)
        XCTAssertTrue(next.waitForExistence(timeout: 15), "Missing \(step) step")
        XCTAssertEqual(next.label, "Continue")
        XCTAssertFalse(app.buttons["Not now"].exists)
        XCTAssertFalse(app.buttons["Allow"].exists)
        XCTAssertFalse(app.buttons["Allow «Always»"].exists)
    }

    private func button(_ step: String) -> XCUIElement {
        app.buttons["onboarding_continue_\(step)"]
    }

    private func systemButton(_ labels: [String]) -> XCUIElement {
        let target = springboard.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 12), "Missing system choice: \(labels)")
        return target
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
