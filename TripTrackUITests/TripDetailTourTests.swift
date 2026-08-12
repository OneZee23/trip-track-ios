import XCTest

/// The trip detail, top to bottom, as it actually renders.
///
/// Most of what this screen shows is conditional — the charts need a varied
/// track, the photo strip needs photos, the reactions need a published trip.
/// Reading the code tells you the conditions; only a scroll tells you which of
/// them a real trip satisfies, and what the result looks like.
final class TripDetailTourTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-seed-map-demo"]
        app.launch()
    }

    private func snap(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func test_detail_tour() {
        let profile = app.buttons.matching(identifier: "tab_profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "no way into Я")
        profile.tap()
        usleep(3_000_000)

        let row = app.buttons.matching(identifier: "profile_trip_row").firstMatch
        var attempts = 0
        while !row.exists && attempts < 6 {
            app.swipeUp(velocity: .slow)
            usleep(900_000)
            attempts += 1
        }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "История must list a trip")
        row.tap()
        usleep(4_000_000)
        snap("01_top")

        for i in 2...8 {
            app.swipeUp(velocity: .slow)
            usleep(1_400_000)
            snap(String(format: "%02d_scroll", i))
        }
    }
}
