import XCTest

/// Screenshot check for the Garage sheet.
///
/// Its nav row was hand-built instead of using the app's `CustomNavBar`, so
/// the controls sat 2pt from a sheet's rounded top edge and read as clipped.
/// Layout like that is only visible in a picture.
///
/// Entry point since 6.1.0: the Гараж section of the «Я» tab, not the gear.
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

        // The Гараж is a section of the «Я» screen itself since 6.1.0 — it used
        // to be a row at the foot of the settings sheet, which is nobody's idea
        // of a place to walk into. The section header's «Весь транспорт ›» kept
        // the retired row's identifier, so the tour still has one thing to tap.
        let garage = app.buttons.matching(identifier: "settings_garage").firstMatch
        for _ in 0..<5 where !garage.isHittable {
            app.swipeUp()
            usleep(600_000)
        }
        XCTAssertTrue(garage.waitForExistence(timeout: 4), "the Я screen must offer the Garage")
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
