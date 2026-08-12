import XCTest

/// Screenshot tour of the trip finish screen.
///
/// It used to be reachable only by driving far enough to clear the junk
/// filter, so every change to it cost a trip outside — and it showed. The
/// «Экран финиша (отладка)» row in settings reopens it for the last saved
/// trip, which is what this drives.
final class FinishScreenTests: XCTestCase {
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

    func test_finish_screen() {
        app.buttons.matching(identifier: "tab_profile").firstMatch.tap()
        usleep(1_500_000)

        let gear = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'gearshape'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 8), "profile has a settings control")
        gear.tap()
        usleep(1_500_000)

        let debugRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'финиша' OR label CONTAINS 'Finish screen'")).firstMatch
        for _ in 0..<6 where !debugRow.exists {
            app.swipeUp()
            usleep(500_000)
        }
        XCTAssertTrue(debugRow.waitForExistence(timeout: 4), "the debug entry must be in settings")
        debugRow.tap()
        usleep(3_000_000)

        snap("01_finish_top")
        XCTAssertTrue(app.buttons.matching(identifier: "summary_done").firstMatch.exists,
                      "the finish screen must be up")

        // The action row is pinned, so it is on screen before any scrolling —
        // that is the whole point of moving it out of the scroll view.
        XCTAssertTrue(app.buttons.matching(identifier: "summary_done").firstMatch.isHittable,
                      "«Готово» must be reachable without scrolling")

        app.swipeUp()
        usleep(1_000_000)
        snap("02_finish_bottom")

        // The description field is the canon's inline note.
        XCTAssertTrue(app.buttons.matching(identifier: "summary_description").firstMatch.exists,
                      "the finish screen must offer a description field")

        let badge = app.buttons.matching(identifier: "summary_badge").firstMatch
        if badge.exists {
            badge.tap()
            usleep(1_500_000)
            snap("03_badge_detail")
        }
    }
}
