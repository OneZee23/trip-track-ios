import XCTest

/// Screenshot check for the Garage sheet.
///
/// Its nav row was hand-built instead of using the app's `CustomNavBar`, so
/// the controls sat 2pt from a sheet's rounded top edge and read as clipped.
/// Layout like that is only visible in a picture.
///
/// Entry point since 0.6.0: the Гараж section of the «Я» tab, not the gear.
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

        // The Гараж is a section of the «Я» screen itself since 0.6.0 — it used
        // to be a row at the foot of the settings sheet, which is nobody's idea
        // of a place to walk into. The section header's «Весь транспорт ›» kept
        // the retired row's identifier, so the tour still has one thing to tap.
        // Since the 2 Oct 2026 review a populated «Я» folds garage, PRO,
        // achievements and clubs under one toggle, so open it first.
        let sections = app.buttons["profile_sections_toggle"].firstMatch
        if sections.waitForExistence(timeout: 5) { sections.tap() }
        let garage = app.buttons.matching(identifier: "settings_garage").firstMatch
        XCTAssertTrue(garage.waitForExistence(timeout: 4), "the Я screen must offer the Garage")
        // Slow drags, not swipeUp: a fling overshoots the header (see
        // ProfileTapTargetsTests).
        let window = app.windows.firstMatch
        for _ in 0..<8 where !garage.isHittable || garage.frame.maxY > window.frame.height - 160 {
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -160)),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
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
