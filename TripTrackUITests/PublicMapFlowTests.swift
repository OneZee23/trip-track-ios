import XCTest

/// Somebody else's map, variant A (0.9.1, owner 22 Oct 2026): «загрузка …
/// криво выглядит» and «карта сама не интерактивная».
///
/// Offline fixture (two drives through France), with the trips held for four
/// seconds (`-debug-slow-foreign-trips`) so the loading state can be looked
/// at. While loading: the sheet shows the skeleton, and no loading car sits
/// on the map. Loaded: a tap on a visited region opens it in the same sheet,
/// × closes it, and a trip row opens the trip.
final class PublicMapFlowTests: XCTestCase {
    func testLoadingThenRegionThenTrip() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-hasCompletedOnboarding", "<true/>", "-debug-foreign-trip",
                                "-debug-foreign-profile", "pro", "-debug-slow-foreign-trips",
                                "-appLanguage", "ru", "-appThemeMode", "light"]
        app.launch()

        let preview = app.staticTexts["Foreign trip preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25))
        preview.tap()
        let pill = app.buttons["detail_author_pill"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 10))
        pill.tap()
        XCTAssertTrue(app.staticTexts["profile_display_name"].firstMatch.waitForExistence(timeout: 10))

        let mapCard = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Карта")).firstMatch
        for _ in 0..<6 where !(mapCard.exists && mapCard.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(mapCard.waitForExistence(timeout: 5))
        mapCard.tap()

        // Loading: the skeleton answers «what is coming» (the car that read as
        // a pin in the middle of the map is gone — checked on the frame).
        let skeleton = app.descendants(matching: .any)["public_map_skeleton"].firstMatch
        XCTAssertTrue(skeleton.waitForExistence(timeout: 5), "The sheet shows the skeleton while loading")
        attach(app, "public_map_loading")

        XCTAssertTrue(skeleton.waitForNonExistence(timeout: 15), "The trips arrive")
        sleep(2) // the camera glides from the recent trips to all of them
        attach(app, "public_map_loaded")

        // A visited region opens in the same sheet. The two drives run down
        // the middle of the fitted map, so its middle is on them.
        let summary = app.descendants(matching: .any)["public_map_summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        let middle = CGPoint(x: window.midX, y: (110 + summary.frame.minY) / 2)
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: middle.x, dy: middle.y)).tap()

        let region = app.descendants(matching: .any)["public_map_region"].firstMatch
        XCTAssertTrue(region.waitForExistence(timeout: 5), "A tap on a visited region opens it")
        sleep(1)
        attach(app, "public_map_region")

        let close = app.buttons["atlas_substate_close"].firstMatch
        XCTAssertTrue(close.exists)
        XCTAssertFalse(app.buttons["atlas_substate_back"].exists,
                       "One way out of the region: «back» is already on the screen and leads to the profile")
        close.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "× returns to the summary")

        // And a trip of the region opens the trip itself.
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: middle.x, dy: middle.y)).tap()
        XCTAssertTrue(region.waitForExistence(timeout: 5))
        let row = app.buttons["atlas_region_trip"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The region lists its trips")
        XCTAssertTrue(row.label.contains("→"), "Rows carry the trip's name, not «Поездка»: \(row.label)")
        row.tap()
        // The map stays in the tree under the cover, so the proof is the
        // trip screen itself.
        XCTAssertTrue(app.scrollViews["detail_content"].firstMatch.waitForExistence(timeout: 10),
                      "The trip opens over the map")
        sleep(1)
        attach(app, "public_map_trip_opened")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
