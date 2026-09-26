import XCTest

/// Tapping a tab must change the screen, not just its selected icon. Also
/// checks that the shared bar disappears for expanded Atlas and trip detail.
final class TabBarNavigationTests: XCTestCase {
    func testTabsRespondAndBarFollowsPresentedScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>",
                                "-seed-map-demo", "-debug-foreign-trip"]
        app.launch()

        func tap(_ id: String) {
            let button = app.buttons[id].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 15), id)
            XCTAssertTrue(button.isHittable, id)
            button.tap()
        }
        func absent(_ element: XCUIElement) {
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        }

        XCTAssertTrue(app.staticTexts["Foreign trip preview"].firstMatch.waitForExistence(timeout: 20))
        tap("tab_maps")
        XCTAssertTrue(app.buttons["atlas_appearance"].waitForExistence(timeout: 15))
        tap("mymap_grabber")
        tap("mymap_grabber")
        XCTAssertTrue(app.textFields["atlas_search"].waitForExistence(timeout: 10))
        absent(app.buttons["tab_home"])
        tap("mymap_close")
        tap("tab_places")
        absent(app.buttons["atlas_appearance"])
        let places = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["places_empty", "places_list", "places_suggestions"])).firstMatch
        XCTAssertTrue(places.waitForExistence(timeout: 10), "The Places screen must actually appear")
        tap("tab_profile")
        let profile = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier IN %@", ["profile_guest_signin", "profile_garage_card", "profile_garage_empty"])).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "The profile must appear regardless of saved sign-in state")
        tap("tab_maps")
        XCTAssertTrue(app.buttons["atlas_appearance"].waitForExistence(timeout: 10))
        tap("tab_record")
        XCTAssertTrue(app.buttons["tracking_back"].waitForExistence(timeout: 10))
        absent(app.buttons["tab_home"])
        tap("tracking_back")
        tap("tab_home")

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        preview.tap()
        XCTAssertTrue(app.buttons["detail_map_expand"].waitForExistence(timeout: 10))
        absent(app.buttons["tab_home"])
        tap("detail_back")
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        tap("tab_maps")
        XCTAssertTrue(app.buttons["atlas_appearance"].waitForExistence(timeout: 10))
    }
}
