import XCTest

/// Screenshot tour for «Запись поездки». The recording screen is mostly map
/// with a floating panel over it, and the things that go wrong on it —
/// a card sitting under the home indicator, a slider that reads thin on a
/// wide phone, controls crowding each other — are all invisible in code and
/// obvious in a picture.
final class TrackingTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_idle_screen() {
        let record = app.buttons.matching(identifier: "tab_record").firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10), "the Record tab must be reachable")
        record.tap()
        usleep(3_000_000)

        snap("01_idle")

        XCTAssertTrue(app.buttons.matching(identifier: "tracking_back").firstMatch.exists,
                      "the tab bar is hidden here, so the chevron is the only way out")
    }
}
