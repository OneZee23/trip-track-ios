import XCTest

/// Screenshot check for the Garage sheet.
///
/// Its nav row was hand-built instead of using the app's `CustomNavBar`, so
/// the controls sat 2pt from a sheet's rounded top edge and read as clipped.
/// Layout like that is only visible in a picture.
final class GarageTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    func test_garage_nav_row() {
        app.buttons.matching(identifier: "tab_profile").firstMatch.tap()
        usleep(1_500_000)

        // The Garage lives behind the gear, not on the profile itself. The
        // gear sits inside the header, which owns the identifier, so it is
        // matched by its glyph label.
        let gear = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'gearshape'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 8), "profile has a settings control")
        gear.tap()
        usleep(1_500_000)

        let garage = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Гараж' OR label CONTAINS 'Garage'")).firstMatch
        for _ in 0..<4 where !garage.exists {
            app.swipeUp()
            usleep(600_000)
        }
        XCTAssertTrue(garage.waitForExistence(timeout: 4), "settings must offer the Garage")
        garage.tap()
        usleep(2_000_000)

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "01_garage"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(app.buttons.matching(identifier: "garage_add").firstMatch.exists,
                      "the «+» control must be on the canon nav bar")

        // The vehicle card is the other half of this tour: its top bar and the
        // stereo-status block are both layout that only a picture catches.
        let card = app.buttons.matching(identifier: "garage_card").firstMatch
        guard card.waitForExistence(timeout: 4) else { return }
        card.tap()
        usleep(2_000_000)

        let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detail.name = "02_vehicle_card"
        detail.lifetime = .keepAlways
        add(detail)

        XCTAssertTrue(app.otherElements.matching(identifier: "vehicle_stereo_status").firstMatch.exists
                      || app.staticTexts.matching(identifier: "vehicle_stereo_status").firstMatch.exists,
                      "the stereo state must be stated, not left to silence")
    }
}
